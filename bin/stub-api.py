#!/usr/bin/env python3
"""Stub Anthropic /v1/messages server for permission-path probing.

Emits exactly one canned Bash tool_use, then ends the turn, so a Claude Code
run becomes a deterministic test of the permission layer with no model involved.
Speaks SSE when the request asks for stream:true, plain JSON otherwise.

Usage: stub.py --port N --command '<bash command>' [--log FILE]
"""
import argparse, json, threading, http.server

ap = argparse.ArgumentParser(description=__doc__,
    formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('--port', type=int, required=True, help='port to listen on')
ap.add_argument('--command', required=True, help='bash command to request')
ap.add_argument('--log', help='append request trace here')
args = ap.parse_args()

state = {'sent': False}
lock = threading.Lock()
TID = 'toolu_stub1'


def blocks(use_tool):
    if use_tool:
        return [{"type": "tool_use", "id": TID, "name": "Bash",
                 "input": {"command": args.command, "description": "stub probe"}}], "tool_use"
    return [{"type": "text", "text": "STUB_DONE"}], "end_turn"


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def do_GET(self):
        self._json({"data": [{"id": "claude-opus-5", "type": "model"}]})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('content-length', 0))).decode('utf-8', 'replace')
        try:
            j = json.loads(body)
        except Exception:
            j = {}
        with lock:
            use_tool = TID not in body and not state['sent']
            if use_tool:
                state['sent'] = True
        if args.log:
            with open(args.log, 'a') as fh:
                fh.write("REQ nmsgs=%d stream=%s -> %s\n" % (
                    len(j.get('messages') or []), j.get('stream'),
                    'TOOL_USE' if use_tool else 'end_turn'))
        content, stop = blocks(use_tool)
        if j.get('stream'):
            self._sse(content, stop)
        else:
            self._json({"id": "msg_stub", "type": "message", "role": "assistant",
                        "model": "claude-opus-5", "content": content,
                        "stop_reason": stop, "stop_sequence": None,
                        "usage": {"input_tokens": 1, "output_tokens": 1}})

    def _sse(self, content, stop):
        self.send_response(200)
        self.send_header('content-type', 'text/event-stream')
        self.send_header('cache-control', 'no-cache')
        self.end_headers()

        def ev(name, data):
            self.wfile.write(("event: %s\ndata: %s\n\n" % (name, json.dumps(data))).encode())
            self.wfile.flush()

        ev("message_start", {"type": "message_start", "message": {
            "id": "msg_stub", "type": "message", "role": "assistant",
            "model": "claude-opus-5", "content": [], "stop_reason": None,
            "stop_sequence": None,
            "usage": {"input_tokens": 1, "output_tokens": 1}}})
        for i, c in enumerate(content):
            if c["type"] == "tool_use":
                ev("content_block_start", {"type": "content_block_start", "index": i,
                    "content_block": {"type": "tool_use", "id": c["id"],
                                      "name": c["name"], "input": {}}})
                ev("content_block_delta", {"type": "content_block_delta", "index": i,
                    "delta": {"type": "input_json_delta",
                              "partial_json": json.dumps(c["input"])}})
            else:
                ev("content_block_start", {"type": "content_block_start", "index": i,
                    "content_block": {"type": "text", "text": ""}})
                ev("content_block_delta", {"type": "content_block_delta", "index": i,
                    "delta": {"type": "text_delta", "text": c["text"]}})
            ev("content_block_stop", {"type": "content_block_stop", "index": i})
        ev("message_delta", {"type": "message_delta",
                             "delta": {"stop_reason": stop, "stop_sequence": None},
                             "usage": {"output_tokens": 1}})
        ev("message_stop", {"type": "message_stop"})

    def _json(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)


http.server.ThreadingHTTPServer(('127.0.0.1', args.port), H).serve_forever()
