"""Read public verification responses using curl, including complete chunked bodies."""
import email
import io
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request
import urllib.response
from urllib.parse import urlsplit

AGENT = 'TypingPet-Website-Verifier/1.0 (+https://github.com/ynifamily3/TypingPetMac)'


def urlopen(request, timeout=30):
    if isinstance(request, urllib.request.Request):
        url, method, headers = request.full_url, request.get_method(), dict(request.header_items())
        data = request.data
        if data is not None and not isinstance(data, bytes):
            raise ValueError('Verification request bodies must be bytes')
    else:
        url, method, headers, data = request, 'GET', {}, None
    if urlsplit(url).scheme != 'https' or method not in {'GET', 'HEAD', 'POST', 'PUT', 'DELETE'}:
        raise ValueError('Unexpected verification request')
    print(f'Verifying {method} {urlsplit(url).netloc}{urlsplit(url).path}', flush=True)
    with tempfile.TemporaryDirectory(prefix='typingpet-web-read-') as folder:
        root = Path(folder)
        args = ['curl', '--silent', '--show-error', '--location', '--retry', '2', '--retry-delay', '1',
                '--proto', '=https', '--proto-redir', '=https',
                '--connect-timeout', '10', '--max-time', str(max(60, timeout)), '--user-agent', AGENT,
                '--dump-header', str(root / 'headers'), '--output', str(root / 'body'),
                '--write-out', '%{http_code}\n%{url_effective}']
        if method == 'HEAD':
            args.append('--head')
        elif method != 'GET':
            args.extend(['--request', method])
        for key, value in headers.items():
            args.extend(['--header', key + ': ' + value])
        if data is None:
            output = subprocess.check_output([*args, url], text=True)
        else:
            # Keep payload bytes out of command arguments and preserve the original request method.
            args.extend(['--data-binary', '@-'])
            output = subprocess.check_output([*args, url], input=data).decode('utf-8')
        code, final = output.split('\n', 1)
        code = int(code)
        blocks = [block for block in (root / 'headers').read_bytes().replace(b'\r\n', b'\n').split(b'\n\n')
                  if block.startswith(b'HTTP/')]
        if not blocks:
            raise RuntimeError('Missing verification response headers')
        response_headers = email.message_from_bytes(blocks[-1].split(b'\n', 1)[1])
        payload = root / 'body'
        if not payload.exists() and method != 'HEAD' and code not in {204, 304}:
            raise RuntimeError('Missing verification response body')
        body = io.BytesIO(payload.read_bytes() if method != 'HEAD' and payload.exists() else b'')
        if code >= 400 or code == 304:
            raise urllib.error.HTTPError(final, code, 'HTTP response', response_headers, body)
        return urllib.response.addinfourl(body, response_headers, final, code)
