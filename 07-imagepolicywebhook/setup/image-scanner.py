#!/usr/bin/env python3
# Minimal ImagePolicyWebhook backend ("container image scanner").
# Rejects images that use :latest or have no tag; allows everything else.
# Runs on the node as systemd service "image-scanner", HTTPS on :8081.
import json, ssl, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/var/log/imagepolicy/scanner.log"
CERT_DIR = "/etc/image-scanner"

def vulnerable(image):
    if "@sha256:" in image:
        return False
    last = image.rsplit("/", 1)[-1]
    return ":" not in last or last.endswith(":latest")

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        review = json.loads(body or b"{}")
        spec = review.get("spec", {})
        images = [c.get("image", "") for c in spec.get("containers", [])]
        bad = [i for i in images if vulnerable(i)]
        status = {"allowed": not bad}
        if bad:
            status["reason"] = "image scanner rejected vulnerable image(s): " + ", ".join(bad)
        out = json.dumps({"apiVersion": review.get("apiVersion", "imagepolicy.k8s.io/v1alpha1"),
                          "kind": "ImageReview", "status": status}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(out)
        with open(LOG, "a") as f:
            f.write("%s ns=%s images=%s allowed=%s\n" % (
                datetime.datetime.utcnow().isoformat(timespec="seconds"),
                spec.get("namespace", "?"), ",".join(images), not bad))

    def log_message(self, *args):
        pass

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT_DIR + "/server.crt", CERT_DIR + "/server.key")
srv = HTTPServer(("0.0.0.0", 8081), Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
