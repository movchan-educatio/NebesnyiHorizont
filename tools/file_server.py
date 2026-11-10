import os
import re
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class ResumableHTTPRequestHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self):
        self.send_file(head_only=True)

    def do_GET(self):
        clean_path = self.path.split("?")[0].lstrip("/")
        if clean_path in ("", "index.html"):
            index_path = os.path.join(self.directory, "index.html")
            if os.path.exists(index_path):
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                with open(index_path, "rb") as f:
                    content = f.read()
                self.send_header("Content-Length", str(len(content)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(content)
                return
        self.send_file(head_only=False)

    def send_file(self, head_only=False):
        clean_path = self.path.split("?")[0].lstrip("/")
        if not clean_path:
            clean_path = "index.html"
        file_path = os.path.join(self.directory, clean_path)

        if not os.path.exists(file_path) or os.path.isdir(file_path):
            self.send_error(404, "File not found")
            return

        file_size = os.path.getsize(file_path)
        range_header = self.headers.get("Range")

        start = 0
        end = file_size - 1
        status_code = 200

        if range_header:
            m = re.match(r"bytes=(\d+)-(\d*)", range_header)
            if m:
                status_code = 206
                start = int(m.group(1))
                if m.group(2):
                    end = int(m.group(2))

        if start >= file_size or end >= file_size or start > end:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{file_size}")
            self.end_headers()
            return

        content_length = end - start + 1

        self.send_response(status_code)
        if clean_path.endswith(".ipa"):
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f'attachment; filename="{os.path.basename(clean_path)}"')
        elif clean_path.endswith(".html"):
            self.send_header("Content-Type", "text/html; charset=utf-8")
        elif clean_path.endswith(".png"):
            self.send_header("Content-Type", "image/png")
        else:
            self.send_header("Content-Type", "application/octet-stream")

        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(content_length))

        if status_code == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")

        self.end_headers()

        if head_only:
            return

        try:
            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = content_length
                chunk_size = 256 * 1024  # 256KB chunks
                while remaining > 0:
                    read_len = min(remaining, chunk_size)
                    data = f.read(read_len)
                    if not data:
                        break
                    self.wfile.write(data)
                    remaining -= len(data)
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
            pass
        except Exception as e:
            print(f"[SERVER] Transfer error: {e}", file=sys.stderr)

    def log_message(self, format, *args):
        print(f"[HTTP] {self.client_address[0]} - {format % args}", flush=True)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    directory = sys.argv[2] if len(sys.argv) > 2 else "C:/Users/USER_UA/Desktop"
    
    server_address = ("0.0.0.0", port)
    handler = lambda *args, **kwargs: ResumableHTTPRequestHandler(*args, directory=directory, **kwargs)
    httpd = ThreadingHTTPServer(server_address, handler)
    print(f"Resumable Threaded HTTP Server running on http://0.0.0.0:{port} serving {directory}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
