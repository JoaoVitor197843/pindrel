#!/usr/bin/env python3
"""A tiny stand-in for the GitHub releases API, for test_github_release.sh (no network, no GitHub).

usage: fake_github_api.py <port-file> <token>
The tags GitHub "knows" are seeded with POST /_tags {"tags": [...]}; GET /_state dumps what it holds."""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, token = sys.argv[1], sys.argv[2]
releases = {}
tags = set()
next_id = [1]
R = "/repos/o/r"


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
        path = self.path.split("?")[0]
        if path == "/_state":
            return self.send(200, releases)
        if path == "/_tags" and method == "POST":
            tags.update(json.loads(self.body())["tags"])
            return self.send(200, {})
        if self.headers.get("Authorization") != "Bearer " + token:
            return self.send(401, {"message": "Bad credentials"})
        uploads = path.startswith("/uploads")
        if uploads:
            path = path[len("/uploads"):]
        if not path.startswith(R):
            return self.send(404, {"message": "Not Found"})
        path = path[len(R):]
        m = re.fullmatch(r"/git/ref/tags/(.+)", path)
        if m and method == "GET":
            return self.send(200 if m.group(1) in tags else 404, {"ref": m.group(1)})
        m = re.fullmatch(r"/releases/tags/(.+)", path)
        if m and method == "GET":
            for r in releases.values():
                if r["tag_name"] == m.group(1):
                    return self.send(200, r)
            return self.send(404, {"message": "Not Found"})
        if path == "/releases" and method == "POST":
            req = json.loads(self.body())
            if req["tag_name"] not in tags:
                return self.send(422, {"message": "tag does not exist (GitHub would create it from the default branch)"})
            r = dict(req, id=next_id[0], assets=[])
            next_id[0] += 1
            releases[r["id"]] = r
            return self.send(201, r)
        m = re.fullmatch(r"/releases/(\d+)", path)
        if m and method == "PATCH":
            r = releases.get(int(m.group(1)))
            if not r:
                return self.send(404, {"message": "Not Found"})
            r.update(json.loads(self.body()))
            return self.send(200, r)
        m = re.fullmatch(r"/releases/(\d+)/assets", path)
        if m:
            r = releases.get(int(m.group(1)))
            if not r:
                return self.send(404, {"message": "Not Found"})
            if method == "GET":
                return self.send(200, r["assets"])
            if method == "POST" and uploads:
                name = re.search(r"name=([^&]+)", self.path).group(1)
                data = self.body()
                if any(a["name"] == name for a in r["assets"]):
                    return self.send(422, {"message": "already_exists"})
                a = {"id": next_id[0], "name": name, "size": len(data), "data": data.decode("latin-1")}
                next_id[0] += 1
                r["assets"].append(a)
                return self.send(201, {k: a[k] for k in ("id", "name", "size")})
        m = re.fullmatch(r"/releases/assets/(\d+)", path)
        if m and method == "DELETE":
            for r in releases.values():
                r["assets"] = [a for a in r["assets"] if a["id"] != int(m.group(1))]
            return self.send(204, {})
        return self.send(404, {"message": "Not Found"})

    do_GET = lambda self: self.route("GET")
    do_POST = lambda self: self.route("POST")
    do_PATCH = lambda self: self.route("PATCH")
    do_DELETE = lambda self: self.route("DELETE")


server = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(server.server_address[1]))
server.serve_forever()
