#!/usr/bin/env python3
"""Verify credentialed URLSession requests never follow redirects, using only fake local data."""
import http.server
import os
from pathlib import Path
import subprocess
import threading

source_requests = []
redirect_requests = []


class Receiver(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def receive(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        redirect_requests.append(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{}')

    do_GET = do_POST = receive


class Source(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def receive(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        source_requests.append((self.path, self.headers.get('Authorization'),
                                self.headers.get('x-api-key'), bool(body)))
        self.send_response(307)
        # Different host spelling and port exercise a cross-origin redirect.
        self.send_header('Location', f'http://localhost:{receiver.server_port}/must-not-receive')
        self.send_header('Content-Length', '0')
        self.end_headers()

    do_GET = do_POST = receive


receiver = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
source = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Source)
for server in (source, receiver):
    threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = dict(os.environ, PAPERCLIP_NETWORK_TEST_ORIGIN=f'http://127.0.0.1:{source.server_port}')
    subprocess.run(['swift', 'test', '--filter', 'TransportSecurityTests.testRealTransportRejectsRedirects'],
                   cwd=Path(__file__).resolve().parents[1] / 'PaperclipKit', env=env, check=True)
    assert redirect_requests == [], 'A redirect target received a request'
    assert source_requests == [
        ('/api/health', 'Bearer fixture-board-key', None, False),
        ('/api/companies/fixture-company/issues', 'Bearer fixture-board-key', None, True),
        ('/avatar', 'Bearer fixture-board-key', None, False),
        ('/api/cli-auth/challenges', None, None, True),
        ('/v1/messages', None, 'fixture-llm-key', True),
        ('/chat/completions', 'Bearer fixture-llm-key', None, True),
    ], 'Unexpected source request sequence or synthetic authentication headers'
    print('PASS: six real Board/auth/content/LLM requests stopped at 307; zero requests, keys or bodies reached the redirect target.')
finally:
    for server in (source, receiver):
        server.shutdown()
        server.server_close()
