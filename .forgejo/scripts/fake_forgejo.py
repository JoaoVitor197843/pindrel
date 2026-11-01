#!/usr/bin/env python3
"""A tiny stand-in for the Forgejo releases API, for test_release.sh (no network, no Forgejo).

usage: fake_forgejo.py <port-file> <token>
Writes the port it listens on to <port-file>; GET /_state dumps what it holds."""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, token = sys.argv[1], sys.argv[2]
releases = {}  # id -> release
next_id = [1]
BASE = "/api/v1/repos/o/r"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def route(self, method):
        if self.path == "/_state":
            return self.send(200, releases)
        if self.headers.get("Authorization") != "token " + token:
            return self.send(401, {"message": "token is required"})
        path = self.path.split("?")[0]
        if not path.startswith(BASE):
            return self.send(404, {"message": "not found"})
        path = path[len(BASE):]
        m = re.fullmatch(r"/releases/tags/(.+)", path)
        if m and method == "GET":
            for r in releases.values():
                if r["tag_name"] == m.group(1):
                    return self.send(200, r)
            return self.send(404, {"message": "release not found"})
        if path == "/releases" and method == "POST":
            req = json.loads(self.body())
            if any(r["tag_name"] == req["tag_name"] for r in releases.values()):
                return self.send(409, {"message": "release exists"})
            r = dict(req, id=next_id[0], assets=[])
            next_id[0] += 1
            releases[r["id"]] = r
            return self.send(201, r)
        m = re.fullmatch(r"/releases/(\d+)", path)
        if m and method == "PATCH":
            r = releases.get(int(m.group(1)))
            if not r:
                return self.send(404, {"message": "release not found"})
            r.update(json.loads(self.body()))
            return self.send(200, r)
        m = re.fullmatch(r"/releases/(\d+)/assets", path)
        if m:
            r = releases.get(int(m.group(1)))
            if not r:
                return self.send(404, {"message": "release not found"})
            if method == "GET":
                return self.send(200, r["assets"])
            if method == "POST":
                name = re.search(r"name=([^&]+)", self.path).group(1)
                raw = self.body()
                if any(a["name"] == name for a in r["assets"]):
                    return self.send(409, {"message": "asset exists"})
                a = {"id": next_id[0], "name": name, "size": len(raw), "raw": raw.decode("latin-1")}
                next_id[0] += 1
                r["assets"].append(a)
                return self.send(201, a)
        m = re.fullmatch(r"/releases/(\d+)/assets/(\d+)", path)
        if m and method == "DELETE":
            r = releases.get(int(m.group(1)))
            r["assets"] = [a for a in r["assets"] if a["id"] != int(m.group(2))]
            return self.send(204, {})
        return self.send(404, {"message": "not found"})

    do_GET = lambda self: self.route("GET")
    do_POST = lambda self: self.route("POST")
    do_PATCH = lambda self: self.route("PATCH")
    do_DELETE = lambda self: self.route("DELETE")


server = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(server.server_address[1]))
server.serve_forever()
