"""Exercise the deployed nginx template and publication rollback without live changes."""
import copy
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

import deploy
from downloads import IMMUTABLE_CACHE, download_targets, latest_url, render_targets

WEBSITE = Path(__file__).resolve().parents[1]
NGINX = shutil.which('nginx')


def release():
    zip_data, dmg_data = b'zip fixture for download verification', b'dmg fixture for download verification'
    metadata = {
        'version': '0.17.1', 'build': 27,
        'url': 'https://pet.miel.ing/update/production/TypingPet-0.17.1-27-arm64.zip',
        'githubUrl': 'https://github.com/ynifamily3/TypingPetMac/releases/download/v0.17.1/TypingPetMac-v0.17.1-arm64.zip',
        'size': len(zip_data), 'sha256': hashlib.sha256(zip_data).hexdigest(),
        'dmg': {
            'url': 'https://pet.miel.ing/update/production/TypingPetMac-v0.17.1-arm64-installer.dmg',
            'githubUrl': 'https://github.com/ynifamily3/TypingPetMac/releases/download/v0.17.1/TypingPetMac-v0.17.1-arm64-installer.dmg',
            'size': len(dmg_data), 'sha256': hashlib.sha256(dmg_data).hexdigest(),
        },
    }
    return metadata, zip_data, dmg_data


class TargetValidation(unittest.TestCase):
    def test_no_dmg_defaults_to_zip_without_silently_replacing_explicit_dmg(self):
        metadata, _, _ = release()
        del metadata['dmg']
        targets = download_targets(metadata)
        self.assertEqual(targets['github:auto'], metadata['githubUrl'])
        self.assertEqual(targets['direct:auto'], metadata['url'])
        self.assertNotIn('github:dmg', targets)
        self.assertNotIn('direct:dmg', targets)

    def test_destinations_must_match_release_and_repository(self):
        metadata, _, _ = release()
        for section, key, value in (
            (None, 'url', metadata['url'] + '?different=1'),
            (None, 'githubUrl', metadata['githubUrl'].replace('ynifamily3', 'another-owner')),
            ('dmg', 'url', metadata['dmg']['url'].replace('pet.miel.ing', 'example.com')),
            ('dmg', 'githubUrl', metadata['dmg']['githubUrl'].replace('v0.17.1/', 'v0.17.0/')),
            (None, 'version', '0.17.1; return 302 https://example.com'),
        ):
            with self.subTest(section=section, key=key):
                changed = copy.deepcopy(metadata)
                (changed[section] if section else changed)[key] = value
                with self.assertRaises(ValueError):
                    render_targets(changed)


@unittest.skipUnless(NGINX, 'nginx is required for the live-template integration tests')
class NginxDownloads(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='typing-pet-download-test-')
        cls.root = Path(cls.tmp.name).resolve()
        cls.metadata, zip_data, dmg_data = release()
        cls.targets = download_targets(cls.metadata)
        production = cls.root / 'update/production'
        production.mkdir(parents=True)
        for asset, data in ((cls.metadata, zip_data), (cls.metadata['dmg'], dmg_data)):
            (production / asset['url'].rsplit('/', 1)[-1]).write_bytes(data)
        (production / 'latest.json').write_text('{}')
        (cls.root / 'targets.conf').write_bytes(render_targets(cls.metadata))
        (cls.root / 'legacy.conf').write_text(f'return 302 {cls.metadata["url"]};\n')
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            cls.port = listener.getsockname()[1]
        template = (WEBSITE / 'nginx/typing-pet-downloads.conf').read_text().split('# Dedicated HTTP redirect listener')[0]
        template = template.replace('listen 172.30.1.1:8444 ssl;', f'listen 127.0.0.1:{cls.port};')
        template = template.replace('listen 127.0.0.1:8444 ssl;', '')
        template = re.sub(r'^\s*ssl_.*$', '', template, flags=re.MULTILINE)
        template = re.sub(r'^\s*access_log .*$', '    access_log off;', template, flags=re.MULTILINE)
        template = re.sub(r'^\s*error_log .*$', f'    error_log {cls.root}/error.log warn;', template, flags=re.MULTILINE)
        template = template.replace('/Users/miel/.config/nginx/snippets/typing-pet-download-targets.conf', str(cls.root / 'targets.conf'))
        template = template.replace('/Users/miel/.config/nginx/snippets/typing-pet-latest.conf', str(cls.root / 'legacy.conf'))
        template = template.replace('/Users/miel/TypingPetUpdate/', str(cls.root / 'update') + '/')
        config = cls.root / 'nginx.conf'
        config.write_text(f'daemon off;\nmaster_process off;\npid {cls.root}/nginx.pid;\nerror_log {cls.root}/error.log;\nevents {{}}\nhttp {{\n{template}\n}}\n')
        cls.process = subprocess.Popen([NGINX, '-p', str(cls.root), '-c', str(config)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cls.addClassCleanup(cls.cleanup)
        for _ in range(100):
            if cls.process.poll() is not None:
                raise RuntimeError(cls.process.communicate()[1].decode())
            try:
                cls.request('/latest')
                break
            except OSError:
                time.sleep(.02)
        else:
            raise RuntimeError('Isolated nginx failed to start')

    @classmethod
    def cleanup(cls):
        cls.process.terminate()
        cls.process.communicate(timeout=5)
        cls.tmp.cleanup()

    @classmethod
    def request(cls, path, method='GET', headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', cls.port, timeout=3)
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def assert_cache(self, headers, expected):
        for name in ('Cache-Control', 'CDN-Cache-Control', 'Cloudflare-CDN-Cache-Control'):
            self.assertEqual(headers.get(name), expected, name)

    def test_all_sources_formats_and_methods_redirect_without_proxying(self):
        for source in ('github', 'direct'):
            for kind in ('dmg', 'zip'):
                for query in (f'from={source}&type={kind}', f'type={kind}&from={source}'):
                    for method in ('GET', 'HEAD'):
                        with self.subTest(query=query, method=method):
                            status, headers, _ = self.request('/latest?' + query, method)
                            self.assertEqual(status, 302)
                            self.assertEqual(headers['Location'], self.targets[f'{source}:{kind}'])
                            self.assert_cache(headers, 'no-store')

    def test_defaults_and_legacy_zip_entry(self):
        for path, key in (('/latest', 'github:dmg'), ('/latest?from=direct', 'direct:dmg'),
                          ('/latest?type=zip', 'github:zip'), ('/download/latest', 'direct:zip')):
            status, headers, _ = self.request(path)
            self.assertEqual(status, 302)
            self.assertEqual(headers['Location'], self.targets[key])
            self.assert_cache(headers, 'no-store')

    def test_invalid_queries_and_methods_are_not_cached(self):
        for query in ('from=elsewhere', 'type=exe', 'from=', 'type=', 'From=github',
                      'from=GitHub', 'from=github&from=direct', 'type=dmg&type=zip',
                      'from=github&type=dmg&extra=1', 'url=https://example.com', 'type=%64mg',
                      'type=zip&', 'type=zip%26from=github'):
            with self.subTest(query=query):
                status, headers, _ = self.request('/latest?' + query)
                self.assertEqual(status, 400)
                self.assertNotIn('Location', headers)
                self.assert_cache(headers, 'no-store')
        status, headers, _ = self.request('/latest?from=github&type=dmg', 'POST')
        self.assertEqual(status, 405)
        self.assert_cache(headers, 'no-store')

    def test_fixed_assets_support_immutable_full_range_and_conditional_responses(self):
        for kind, content_type in (('zip', 'application/zip'), ('dmg', 'application/x-apple-diskimage')):
            path = self.targets[f'direct:{kind}'].removeprefix('https://pet.miel.ing')
            with self.subTest(kind=kind):
                status, headers, data = self.request(path)
                self.assertEqual(status, 200)
                self.assertEqual(headers['Content-Type'], content_type)
                self.assert_cache(headers, IMMUTABLE_CACHE)
                status, ranged, body = self.request(path, headers={'Range': 'bytes=0-3'})
                self.assertEqual((status, body), (206, data[:4]))
                self.assert_cache(ranged, IMMUTABLE_CACHE)
                status, conditional, body = self.request(path, headers={'If-None-Match': headers['ETag']})
                self.assertEqual((status, body), (304, b''))
                self.assert_cache(conditional, IMMUTABLE_CACHE)

    def test_missing_assets_are_not_immutable_and_feed_remains_revalidated(self):
        for path in ('/update/production/TypingPet-9.9.9-999-arm64.zip',
                     '/update/production/TypingPetMac-v9.9.9-arm64-installer.dmg', '/update/.env', '/unknown'):
            status, headers, _ = self.request(path)
            self.assertEqual(status, 404)
            self.assert_cache(headers, 'no-store')
        status, headers, _ = self.request('/update/production/latest.json')
        self.assertEqual(status, 200)
        self.assertEqual(headers['Cache-Control'], 'no-cache')
        self.assertEqual(headers['CDN-Cache-Control'], 'no-store')


class PublicationRollback(unittest.TestCase):
    def test_reload_failure_restores_all_configs_and_website_pointer(self):
        with tempfile.TemporaryDirectory(prefix='typing-pet-deploy-test-') as temp:
            root = Path(temp)
            website, home, destination = root / 'website', root / 'home', root / 'published'
            metadata, zip_data, dmg_data = release()
            production = home / 'TypingPetUpdate/production'
            production.mkdir(parents=True)
            (production / 'latest.json').write_text(json.dumps(metadata))
            for asset, data in ((metadata, zip_data), (metadata['dmg'], dmg_data)):
                (production / asset['url'].rsplit('/', 1)[-1]).write_bytes(data)
            for path, data in (('src/generated/release.json', json.dumps(metadata)), ('src/locales.json', '{"ko": {}}'),
                               ('dist/ko/index.html', 'new home'), ('dist/ko/changelog/index.html', 'new notes'),
                               ('dist/assets/social-preview.png', 'fixture')):
                file = website / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(data)
            shutil.copytree(WEBSITE / 'nginx', website / 'nginx')
            old_release = destination / 'releases/previous'
            old_release.mkdir(parents=True)
            (destination / 'current').symlink_to(old_release)
            constants = {'WEBSITE': website, 'HOME': home, 'DESTINATION': destination,
                         'NGINX_CONFIG': root / 'nginx.conf', 'SITE_CONFIG': root / 'site.conf',
                         'DOWNLOAD_CONFIG': root / 'downloads.conf', 'DOWNLOAD_TARGETS': root / 'targets.conf',
                         'REDIRECT': root / 'legacy.conf'}
            for name in ('SITE_CONFIG', 'DOWNLOAD_CONFIG', 'REDIRECT'):
                constants[name].write_text('previous ' + name)
            calls = []
            def run(*args):
                calls.append(args)
                if len(calls) == 2:
                    raise OSError('Simulated reload failure')
            with patch.multiple(deploy, **constants), patch.object(deploy, 'run', side_effect=run):
                with self.assertRaisesRegex(OSError, 'Simulated reload failure'):
                    deploy.main()
            self.assertEqual(os.readlink(destination / 'current'), str(old_release))
            for name in ('SITE_CONFIG', 'DOWNLOAD_CONFIG', 'REDIRECT'):
                self.assertEqual(constants[name].read_text(), 'previous ' + name)
            self.assertFalse(constants['DOWNLOAD_TARGETS'].exists())
            self.assertEqual([args[1] for args in calls], ['-t', '-s', '-t', '-s'])
            self.assertFalse(list(destination.glob('.current-*')))


if __name__ == '__main__':
    unittest.main()
