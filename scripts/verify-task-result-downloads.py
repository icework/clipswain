#!/usr/bin/env python3
"""Exercise real URLSession downloads against disposable localhost data; no live credentials."""
import http.server
import os
from pathlib import Path
import subprocess
import threading

requests = []


class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        requests.append((self.path, self.headers.get('Authorization')))
        if self.headers.get('Authorization') != 'Bearer fixture-download-token':
            self.send_error(401)
            return
        if self.path == '/api/attachments/file/content':
            body = 'Fixture attachment: 中文 report\n'.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == '/api/attachments/redirect/content':
            self.send_response(302)
            self.send_header('Location', '/must-not-follow-redirect')
            self.end_headers()
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error":"Fixture attachment missing"}')


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = dict(os.environ, PAPERCLIP_ATTACHMENT_TEST_ORIGIN=f'http://127.0.0.1:{server.server_port}')
    subprocess.run(['swift', 'test', '--filter', 'IssueDeliverablesTests.testRealAttachmentDownload'],
                   cwd=Path(__file__).resolve().parents[1] / 'PaperclipKit', env=env, check=True)
    assert [path for path, _ in requests] == [
        '/api/attachments/redirect/content', '/api/attachments/missing/content', '/api/attachments/file/content'
    ], requests
    print('PASS: authenticated file download, JSON error and blocked redirect; fixture only.')
finally:
    server.shutdown()
    server.server_close()
