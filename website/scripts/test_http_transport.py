import unittest
from pathlib import Path
from unittest.mock import patch
import urllib.request
import urllib.error
from http_transport import urlopen


class HTTPTransportTests(unittest.TestCase):
    def response(self, status, body=b'payload', final='https://example.com/final', omit=False):
        def execute(args, **kwargs):
            self.command = args
            headers = Path(args[args.index('--dump-header') + 1])
            headers.write_bytes(b'HTTP/1.1 302 Found\r\nLocation: ' + final.encode() + b'\r\n\r\n'
                                + f'HTTP/2 {status}\r\nContent-Type: application/octet-stream\r\nETag: "test"\r\n\r\n'.encode())
            if not omit:
                Path(args[args.index('--output') + 1]).write_bytes(body)
            return f'{status}\n{final}'
        return patch('http_transport.subprocess.check_output', side_effect=execute)

    def test_complete_body_final_redirect_and_range_header_are_preserved(self):
        with self.response(206, b'012345'):
            with urlopen(urllib.request.Request('https://example.com/file', headers={'Range': 'bytes=0-5'})) as result:
                self.assertEqual((result.status, result.read(), result.geturl()), (206, b'012345', 'https://example.com/final'))
                self.assertEqual(result.headers['ETag'], '"test"')
        self.assertIn('Range: bytes=0-5', self.command)
        self.assertIn('--proto-redir', self.command)
        self.assertNotIn('--insecure', self.command)

    def test_conditional_304_without_body_remains_an_http_error(self):
        with self.response(304, omit=True):
            with self.assertRaises(urllib.error.HTTPError) as error:
                urlopen('https://example.com/file')
            self.assertEqual(error.exception.code, 304)
            self.assertEqual(error.exception.headers['ETag'], '"test"')
            self.assertEqual(error.exception.read(), b'')
            error.exception.close()

    def test_status_errors_and_head_semantics_are_preserved(self):
        with self.response(405):
            with self.assertRaises(urllib.error.HTTPError) as error:
                urlopen(urllib.request.Request('https://example.com/file', method='POST'))
            self.assertEqual(error.exception.code, 405)
            error.exception.close()
        with self.response(200, body=b"ignored HEAD header output"):
            with urlopen(urllib.request.Request('https://example.com/file', method='HEAD')) as result:
                self.assertEqual(result.status, 200)
        self.assertIn('--head', self.command)

    def test_json_body_is_sent_on_stdin_with_the_requested_method(self):
        def execute(args, **kwargs):
            self.assertEqual(kwargs["input"], b"{}")
            self.assertIn("--data-binary", args)
            self.assertEqual(args[args.index("--request") + 1], "POST")
            Path(args[args.index("--dump-header") + 1]).write_bytes(b"HTTP/2 405\r\nContent-Length: 0\r\n\r\n")
            Path(args[args.index("--output") + 1]).write_bytes(b"")
            return b"405\nhttps://example.com/"
        with patch("http_transport.subprocess.check_output", side_effect=execute):
            with self.assertRaises(urllib.error.HTTPError) as error:
                urlopen(urllib.request.Request("https://example.com/", data=b"{}", method="POST"))
            self.assertEqual(error.exception.code, 405)
            error.exception.close()

    def test_http_and_bodyless_success_without_a_body_file_are_rejected(self):
        with self.assertRaises(ValueError):
            urlopen('http://example.com')
        with self.response(200, omit=True):
            with self.assertRaises(RuntimeError):
                urlopen('https://example.com')
