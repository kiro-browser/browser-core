#!/usr/bin/env python3
import argparse
import json
import subprocess
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from datetime import datetime, timezone


class UpdateState:
    def __init__(self, repo_root: Path, build_dir: Path, host: str, port: int):
        self.repo_root = repo_root
        self.build_dir = build_dir
        self.host = host
        self.port = port
        self.output_dir = build_dir / "update"
        self.app_bundle = build_dir / "BuildBrowser.app"
        self.zip_path = self.output_dir / "BuildBrowser.zip"
        self.lock = threading.Lock()
        self.cached_commit = None
        self.cached_manifest = None

    def _run(self, args, cwd=None):
        return subprocess.run(
            args,
            cwd=str(cwd or self.repo_root),
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def _current_commit(self):
        out = self._run(["git", "rev-parse", "HEAD"])
        return out.stdout.strip()

    def _commit_count(self):
        out = self._run(["git", "rev-list", "--count", "HEAD"])
        return int(out.stdout.strip())

    def _git_pull(self):
        self._run(["git", "pull", "--ff-only"])

    def _build_app(self):
        self._run(["cmake", "-S", str(self.repo_root), "-B", str(self.build_dir)])
        self._run(["cmake", "--build", str(self.build_dir)])

    def _zip_app(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        if self.zip_path.exists():
            self.zip_path.unlink()
        self._run([
            "ditto",
            "-c",
            "-k",
            "--keepParent",
            str(self.app_bundle),
            str(self.zip_path),
        ])

    def ensure_artifact(self):
        with self.lock:
            self._git_pull()
            new_commit = self._current_commit()
            if self.cached_commit == new_commit and self.zip_path.exists() and self.cached_manifest:
                return self.cached_manifest

            if self.cached_commit != new_commit or not self.zip_path.exists():
                self._build_app()
                self._zip_app()

            build_number = self._commit_count()
            manifest = {
                "name": "BuildBrowser",
                "version": "1.0",
                "build": build_number,
                "gitCommit": new_commit,
                "updatedAt": datetime.now(timezone.utc).isoformat(),
                "bundleURL": f"http://{self.host}:{self.port}/BuildBrowser.zip",
                "notes": "Pulled from git and rebuilt on demand.",
            }
            self.cached_commit = new_commit
            self.cached_manifest = manifest
            return manifest


def make_handler(state: UpdateState):
    class Handler(SimpleHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print("%s - - [%s] %s" % (self.address_string(), self.log_date_time_string(), fmt % args))

        def do_GET(self):
            if self.path in ("/", "/index.html"):
                self._send_json({
                    "name": "BuildBrowser Update Server",
                    "manifest": "/manifest.json",
                    "bundle": "/BuildBrowser.zip",
                })
                return

            if self.path == "/manifest.json":
                try:
                    manifest = state.ensure_artifact()
                    self._send_json(manifest)
                except subprocess.CalledProcessError as exc:
                    self._send_error(500, "Update build failed", exc.stderr or exc.stdout or str(exc))
                return

            if self.path == "/BuildBrowser.zip":
                try:
                    state.ensure_artifact()
                except subprocess.CalledProcessError as exc:
                    self._send_error(500, "Update build failed", exc.stderr or exc.stdout or str(exc))
                    return
                if not state.zip_path.exists():
                    self._send_error(404, "Missing archive", "BuildBrowser.zip was not generated.")
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(state.zip_path.stat().st_size))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                with state.zip_path.open("rb") as fh:
                    self.wfile.write(fh.read())
                return

            super().do_GET()

        def _send_json(self, payload):
            data = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _send_error(self, code, title, detail):
            payload = {
                "error": title,
                "detail": detail,
            }
            data = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

    return Handler


def main():
    parser = argparse.ArgumentParser(description="BuildBrowser git-backed update server")
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]), help="Repository root")
    parser.add_argument("--build-dir", default="build", help="CMake build directory")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host")
    parser.add_argument("--port", type=int, default=8787, help="Bind port")
    args = parser.parse_args()

    repo_root = Path(args.repo).resolve()
    build_dir = Path(args.build_dir)
    if not build_dir.is_absolute():
        build_dir = (repo_root / build_dir).resolve()
    if not (build_dir / "BuildBrowser.app").exists():
        raise SystemExit(f"Missing app bundle at {build_dir / 'BuildBrowser.app'}")

    state = UpdateState(repo_root, build_dir, args.host, args.port)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(state))
    print(f"BuildBrowser update server listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
