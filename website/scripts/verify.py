#!/usr/bin/env python3
"""Verify the live landing pages, social metadata and the real download path."""
import hashlib
import json
from pathlib import Path
import struct
from html.parser import HTMLParser
import urllib.error
import urllib.request
from datetime import datetime, timezone

BASE = 'https://typing-pet.miel.ing'

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta, self.assets, self.lang = {}, [], None
        self.alternates, self.canonical, self.text = {}, None, []
        self.emails = set()

    def handle_data(self, data):
        self.text.append(data)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
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
    headings = {'ko': '타닥타닥.', 'en': 'Tap, tap.', 'ja': 'カタカタ。', 'zh-Hans': '独处的时光，', 'zh-Hant': '獨處的時光，'}
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
            require(page.meta.get('twitter:card') == 'summary_large_image', f'Missing X card: {path}')
            require(page.meta.get('og:image') == BASE + '/assets/social-preview.png', f'Missing OG image: {path}')
            require(page.meta.get('og:image:width') == '1200' and page.meta.get('og:image:height') == '630', f'Wrong declared image size: {path}')
            email_present = 'support@miel.ing' in html or 'support@miel.ing' in page.emails
            require(metadata['version'] in html and email_present and 'Jongkeun Choi' in html, f'Missing release or contact details: {path}')
            result['pages'][path] = {'status': status, 'cache_control': cache,
                                     'og_locale': page.meta['og:locale'], 'og_title': page.meta['og:title']}
            for asset in page.assets:
                if asset in result['assets']:
                    continue
                with urllib.request.urlopen(urllib.request.Request(BASE + asset, method='HEAD'), timeout=20) as response:
                    require(response.status == 200 and 'immutable' in response.headers.get('Cache-Control', ''), f'Asset or cache failed: {asset}')
                    result['assets'][asset] = {'status': response.status, 'cache_control': response.headers['Cache-Control']}
    with urllib.request.urlopen(BASE + '/assets/social-preview.png', timeout=20) as response:
        image = response.read()
        require(image[:8] == b'\x89PNG\r\n\x1a\n', 'OG image is not a PNG')
        dimensions = struct.unpack('>II', image[16:24])
        require(dimensions == (1200, 630), 'OG image is not 1200 by 630')
        result['opengraph_image'] = {'status': response.status, 'dimensions': dimensions, 'type': response.headers['Content-Type']}
    try:
        urllib.request.build_opener(NoRedirect).open('https://pet.miel.ing/download/latest', timeout=20)
        raise RuntimeError('Expected a download redirect')
    except urllib.error.HTTPError as response:
        require(response.code == 302 and response.headers.get('Cache-Control') == 'no-store', 'Wrong redirect cache policy')
        require(response.headers.get('Cloudflare-CDN-Cache-Control') == 'no-store', 'Missing CDN bypass')
        target = response.headers['Location']
        require(target == metadata['url'], 'Latest points to another build')
        result['latest'] = {'status': response.code, 'cache_control': response.headers['Cache-Control'], 'location': target}
    with urllib.request.urlopen('https://pet.miel.ing/download/latest', timeout=40) as response:
        digest = hashlib.sha256(response.read()).hexdigest()
        require(digest == metadata['sha256'], 'Downloaded ZIP differs from the GitHub-verified build')
        require(response.headers.get('Cache-Control') == 'public, max-age=31536000, immutable', 'Wrong ZIP cache policy')
        result['download'] = {'status': response.status, 'sha256': digest, 'cache_control': response.headers['Cache-Control']}
    with urllib.request.urlopen(urllib.request.Request(target, headers={'Range': 'bytes=0-31'}), timeout=20) as response:
        require(response.status == 206 and len(response.read()) == 32, 'Range downloads failed')
        result['range'] = {'status': response.status, 'content_range': response.headers['Content-Range']}
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
