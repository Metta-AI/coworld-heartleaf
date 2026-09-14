"""Prove nine Bedrock requests can run while the first response is held.

Run after compiling tests/bedrock_transport.nim:
    python3 tests/test_bedrock_transport.py --probe out/bedrock_transport

No credentials or provider access: all requests target the local fake sidecar.
"""

import argparse
import json
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote


def run(probe: str, bind_host: str, endpoint_host: str) -> None:
    first_received = [threading.Event() for _ in range(2)]
    all_received = [threading.Event() for _ in range(2)]
    fast_finished = [threading.Event() for _ in range(2)]
    release_first = [threading.Event() for _ in range(2)]
    seats_received = [set(), set()]
    fast_replies = [set(), set()]
    replies = {}
    output = []
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_POST(self):
            match = re.fullmatch(
                r"/model/test/transport-wave-([01])/converse", unquote(self.path)
            )
            if match is None:
                self.send_error(404)
                return
            wave = int(match.group(1))
            seat = int(self.headers["X-Coworld-Player-Slot"])
            self.rfile.read(int(self.headers["Content-Length"]))
            with lock:
                seats_received[wave].add(seat)
                if seat == 0:
                    first_received[wave].set()
                if seats_received[wave] == set(range(9)):
                    all_received[wave].set()
            if seat == 0:
                ready = release_first[wave].wait(15)
            else:
                ready = all_received[wave].wait(15)
            if not ready:
                self.send_error(504, "test barrier did not release")
                return
            body = json.dumps(
                {
                    "output": {
                        "message": {
                            "content": [{"text": '{"action":"keep_gathering_plants"}'}]
                        }
                    }
                }
            ).encode()
            try:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass  # Cleanup after a deliberately failing regression run.

        def log_message(self, *_args):
            pass

    class Server(ThreadingHTTPServer):
        request_queue_size = 32

    server = Server((bind_host, 0), Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    endpoint = f"http://{endpoint_host}:{server.server_port}"
    process = subprocess.Popen(
        [probe, endpoint],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    def read_output():
        for line in process.stdout:
            output.append(line.rstrip())
            try:
                reply = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "tag" not in reply:
                continue
            wave, seat = map(int, reply["tag"].split(":"))
            with lock:
                replies[reply["tag"]] = reply
                if seat != 0 and reply["outcome"] == "Usable":
                    fast_replies[wave].add(seat)
                    if fast_replies[wave] == set(range(1, 9)):
                        fast_finished[wave].set()

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    try:
        for wave in range(2):
            assert first_received[wave].wait(5), (
                f"wave {wave}: first request never reached server"
            )
            process.stdin.write("start remaining seats\n")
            process.stdin.flush()
            assert all_received[wave].wait(5), (
                f"wave {wave}: requests waited behind the held first response; "
                f"received seats {sorted(seats_received[wave])}"
            )
            assert fast_finished[wave].wait(5), (
                f"wave {wave}: fast requests did not finish independently"
            )
            assert f"{wave}:0" not in replies, "first response was not held"
            release_first[wave].set()
        assert process.wait(timeout=5) == 0, "\n".join(output)
        reader.join(timeout=5)
        assert len(replies) == 18, output
        assert all(reply["outcome"] == "Usable" for reply in replies.values()), output
        print(
            "PASS: all nine requests reached the server concurrently in both waves; "
            "eight usable replies arrived before the held first response."
        )
    finally:
        for event in all_received + release_first:
            event.set()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)
        reader.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", default="out/bedrock_transport")
    parser.add_argument("--bind-host", default="127.0.0.1")
    parser.add_argument("--endpoint-host", default="127.0.0.1")
    args = parser.parse_args()
    run(args.probe, args.bind_host, args.endpoint_host)
