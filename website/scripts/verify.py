#!/usr/bin/env python3
"""Verify the live landing pages, social metadata and the real download path."""
import hashlib
import json
import re
from pathlib import Path
import struct
from html.parser import HTMLParser
import urllib.error
import urllib.request
from urllib.parse import urlsplit
from datetime import datetime, timezone
from downloads import IMMUTABLE_CACHE, download_targets, latest_url

BASE = 'https://typing-pet.miel.ing'

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta, self.assets, self.lang = {}, [], None
        self.alternates, self.canonical, self.text = {}, None, []
        self.emails = set()
        self.links = set()

    def handle_data(self, data):
        self.text.append(data)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'a' and attrs.get('href'):
            self.links.add(attrs['href'])
        if tag == 'html':
            self.lang = attrs.get('lang')
        if tag == 'meta':
            self.meta[attrs.get('property', attrs.get('name'))] = attrs.get('content')
        if attrs.get('data-cfemail'):
            encoded = bytes.fromhex(attrs['data-cfemail'])
            if encoded:
                self.emails.add(bytes(value ^ encoded[0] for value in encoded[1:]).decode())
        if tag == 'script' and attrs.get('src', '').startswith('/assets/'):
            self.assets.append(attrs['src'])
        if tag == 'link' and attrs.get('rel') == 'stylesheet':
            self.assets.append(attrs['href'])
        if tag == 'link' and attrs.get('rel') == 'alternate':
            self.alternates[attrs.get('hreflang')] = attrs.get('href')
        if tag == 'link' and attrs.get('rel') == 'canonical':
            self.canonical = attrs.get('href')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    # Identify this publisher explicitly; the proxied zone rejects the generic Python user agent.
    opener = urllib.request.build_opener()
    opener.addheaders = [('User-Agent', 'TypingPet-Website-Verifier/1.0 (+https://github.com/ynifamily3/TypingPetMac)')]
    urllib.request.install_opener(opener)
    metadata = json.loads((Path(__file__).resolve().parents[1] / 'src/generated/release.json').read_text())
    locales = json.loads((Path(__file__).resolve().parents[1] / 'src/locales.json').read_text())
    headings = {'ko': '언제까지나', 'en': 'Always', 'ja': 'いつまでも', 'zh-Hans': '一直', 'zh-Hant': '一直'}
    note_titles = {note['version']: note for note in json.loads((Path(__file__).resolve().parents[1] / 'src/releases.json').read_text())}
    result = {'checked_at': datetime.now(timezone.utc).isoformat(),
              'network_scope': 'Requests from this Mac; independent external checks are separate.',
              'pages': {}, 'assets': {}}
    for language, config in locales.items():
        for suffix in ('', 'changelog/'):
            path = f'/{language}/{suffix}'
            with urllib.request.urlopen(BASE + path, timeout=20) as response:
                html = response.read().decode()
                status, cache = response.status, response.headers.get('Cache-Control')
            page = Page()
            page.feed(html)
            require(status == 200 and page.lang == language, f'Wrong language or status: {path}')
            require(page.meta.get('og:locale') == config['og'], f'Wrong OG locale: {path}')
            require(page.meta.get('og:url') == BASE + path, f'Wrong OG URL: {path}')
            require(page.canonical == BASE + path, f'Wrong canonical URL: {path}')
            for alternate in locales:
                require(page.alternates.get(alternate) == f'{BASE}/{alternate}/{suffix}', f'Missing alternate {alternate}: {path}')
            visible = ''.join(page.text)
            require(note_titles[metadata['version']][language]['title'] in visible, f'Missing translated release notes: {path}')
            if not suffix:
                require(headings[language] in visible, f'Missing translated homepage: {path}')
                require(latest_url('github', 'zip') in page.links, f'Missing ZIP download: {path}')
                if dmg := metadata.get('dmg'):
                    require(latest_url('github', 'dmg') in page.links, f'Missing DMG download: {path}')
                require(latest_url('direct', 'dmg' if metadata.get('dmg') else 'zip') in page.links,
                        f'Missing direct download: {path}')
            require(page.meta.get('twitter:card') == 'summary_large_image', f'Missing X card: {path}')
            require(page.meta.get('og:image') == BASE + '/assets/social-preview.png', f'Missing OG image: {path}')
            require(page.meta.get('og:image:width') == '1200' and page.meta.get('og:image:height') == '630', f'Wrong declared image size: {path}')
            email_present = 'support@miel.ing' in html or 'support@miel.ing' in page.emails
            require(metadata['version'] in html and email_present and 'Jongkeun Choi' in html, f'Missing release or contact details: {path}')
            theme_script = re.search(r'<script src="(/assets/theme-([a-f0-9]{12})\.js)"></script>', html)
            require(theme_script is not None and 'class="theme-toggle"' in html
                    and html.count('aria-haspopup="menu"') == 1, f'Missing header controls: {path}')
            require('role="combobox"' in html and html.count('role="checkbox"') == 1
                    and 'role="switch"' in html, f'Missing accessible form controls: {path}')
            require(theme_script.start() < html.index('rel="stylesheet"'), f'Late theme bootstrap: {path}')
            result['pages'][path] = {'status': status, 'cache_control': cache,
                                     'og_locale': page.meta['og:locale'], 'og_title': page.meta['og:title']}
            for asset in page.assets:
                if asset in result['assets']:
                    continue
                with urllib.request.urlopen(urllib.request.Request(BASE + asset, method='HEAD'), timeout=20) as response:
                    require(response.status == 200 and 'immutable' in response.headers.get('Cache-Control', ''), f'Asset or cache failed: {asset}')
                    result['assets'][asset] = {'status': response.status, 'cache_control': response.headers['Cache-Control']}
                if asset == theme_script[1]:
                    with urllib.request.urlopen(BASE + asset, timeout=20) as response:
                        digest = hashlib.sha256(response.read()).hexdigest()
                    require(digest[:12] == theme_script[2], 'Theme bootstrap fingerprint mismatch')
                    result['assets'][asset]['sha256'] = digest
    with urllib.request.urlopen(BASE + '/assets/social-preview.png', timeout=20) as response:
        image = response.read()
        require(image[:8] == b'\x89PNG\r\n\x1a\n', 'OG image is not a PNG')
        dimensions = struct.unpack('>II', image[16:24])
        require(dimensions == (1200, 630), 'OG image is not 1200 by 630')
        result['opengraph_image'] = {'status': response.status, 'dimensions': dimensions, 'type': response.headers['Content-Type']}
    targets = download_targets(metadata)
    no_redirect = urllib.request.build_opener(NoRedirect)
    no_redirect.addheaders = opener.addheaders

    def redirect(url, target, method='GET'):
        try:
            no_redirect.open(urllib.request.Request(url, method=method), timeout=20)
            raise RuntimeError(f'Expected a download redirect: {url}')
        except urllib.error.HTTPError as response:
            with response:
                require(response.code == 302 and response.headers.get('Location') == target,
                        f'Wrong redirect destination: {url}')
                for header in ('Cache-Control', 'CDN-Cache-Control', 'Cloudflare-CDN-Cache-Control'):
                    require(response.headers.get(header) == 'no-store', f'Wrong redirect {header}: {url}')
                return {'status': response.code, 'cache_control': response.headers['Cache-Control'], 'location': target}

    result['downloads'] = {}
    for kind in ('zip', 'dmg'):
        asset = metadata if kind == 'zip' else metadata.get('dmg')
        if not asset:
            continue
        for source in ('github', 'direct'):
            url = latest_url(source, kind)
            target = targets[f'{source}:{kind}']
            check = redirect(url, target)
            redirect(url, target, 'HEAD')
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
                digest = hashlib.sha256(data).hexdigest()
                require(response.status == 200 and len(data) == asset['size'] and digest == asset['sha256'],
                        f'Download differs from the GitHub-verified build: {url}')
                if source == 'direct':
                    require(response.geturl() == target, f'Direct download left the fixed asset: {url}')
                    for header in ('Cache-Control', 'CDN-Cache-Control', 'Cloudflare-CDN-Cache-Control'):
                        require(response.headers.get(header) == IMMUTABLE_CACHE, f'Wrong fixed asset {header}: {url}')
                    expected_type = 'application/zip' if kind == 'zip' else 'application/x-apple-diskimage'
                    require(response.headers.get_content_type() == expected_type, f'Wrong asset MIME type: {url}')
                    etag = response.headers['ETag']
                else:
                    require(urlsplit(response.geturl()).hostname in ('github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'),
                            f'GitHub download ended outside GitHub: {url}')
                check.update({'download_status': response.status, 'size': len(data), 'sha256': digest,
                              'final_host': urlsplit(response.geturl()).hostname,
                              'asset_cache_control': response.headers.get('Cache-Control')})
            result['downloads'][url] = check
        direct = targets[f'direct:{kind}']
        with urllib.request.urlopen(urllib.request.Request(direct, headers={'Range': 'bytes=0-31'}), timeout=20) as response:
            require(response.status == 206 and len(response.read()) == 32, f'{kind} Range download failed')
            require(response.headers.get('Cache-Control') == IMMUTABLE_CACHE, f'{kind} Range cache failed')
            result['downloads'][latest_url('direct', kind)]['range_status'] = response.status
        try:
            urllib.request.urlopen(urllib.request.Request(direct, headers={'If-None-Match': etag}), timeout=20)
            raise RuntimeError(f'Expected conditional response: {kind}')
        except urllib.error.HTTPError as response:
            with response:
                require(response.code == 304 and response.headers.get('Cache-Control') == IMMUTABLE_CACHE,
                        f'{kind} conditional cache failed')
                result['downloads'][latest_url('direct', kind)]['conditional_status'] = response.code
        with urllib.request.urlopen(asset['checksumUrl'], timeout=20) as response:
            checksum = response.read().decode().split()[0]
            require(checksum == asset['sha256'], f'{kind} checksum differs')

    result['download_defaults'] = {}
    for path, target in (('/latest', targets['github:auto']),
                         ('/latest?from=direct', targets['direct:auto']),
                         ('/latest?type=zip', targets['github:zip']),
                         ('/download/latest', metadata['url'])):
        result['download_defaults'][path] = redirect('https://pet.miel.ing' + path, target)
    result['download_boundaries'] = {}
    for path, method, expected in (
        ('/latest?from=invalid&type=dmg', 'GET', 400),
        ('/latest?from=github&type=exe', 'GET', 400),
        ('/latest?from=github&from=direct&type=zip', 'GET', 400),
        ('/latest?from=github&type=zip&extra=1', 'GET', 400),
        ('/latest?from=github&type=dmg', 'POST', 405),
        ('/update/production/TypingPet-0.0.0-0-arm64.zip', 'HEAD', 404),
        ('/update/production/TypingPetMac-v0.0.0-arm64-installer.dmg', 'HEAD', 404),
    ):
        try:
            no_redirect.open(urllib.request.Request('https://pet.miel.ing' + path, method=method), timeout=20)
            raise RuntimeError(f'Unexpected download request accepted: {method} {path}')
        except urllib.error.HTTPError as response:
            with response:
                require(response.code == expected, f'Wrong download boundary: {method} {path}')
                for header in ('Cache-Control', 'CDN-Cache-Control', 'Cloudflare-CDN-Cache-Control'):
                    require(response.headers.get(header) == 'no-store', f'Cached download error: {path}')
                result['download_boundaries'][f'{method} {path}'] = response.code
    for path in ('/missing-page', '/.env', '/release.json', '/relay/admin', '/relay/flags'):
        try:
            urllib.request.urlopen(BASE + path, timeout=20)
            raise RuntimeError(f'Unexpected public file: {path}')
        except urllib.error.HTTPError as response:
            require(response.code == 404 and response.headers.get('Cache-Control') == 'no-store', f'Unexpected missing-file response: {path}')
    result['analytics_boundaries'] = {}
    for path, method in (('/relay/e/', 'GET'), ('/relay/i/v0/e/', 'GET'), ('/ko/', 'POST'), ('/relay/flags', 'POST')):
        request = urllib.request.Request(BASE + path, method=method, data=b'{}' if method == 'POST' else None)
        try:
            urllib.request.urlopen(request, timeout=20)
            raise RuntimeError(f'Unexpected method accepted: {method} {path}')
        except urllib.error.HTTPError as response:
            require(response.code == 405 and response.headers.get('Cache-Control') == 'no-store', f'Unexpected method policy: {method} {path}')
            result['analytics_boundaries'][f'{method} {path}'] = response.code
    output = Path.home() / 'server/typing-pet-site/verification/verification.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
