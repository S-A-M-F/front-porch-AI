#!/usr/bin/env python3
# Copyright (C) 2026 Front Porch AI
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Lightweight embedding server for Front Porch AI RAG.

Loads nomic-embed-text-v1.5 via sentence-transformers (ONNX backend) and
serves an OpenAI-compatible /v1/embeddings endpoint on port 5055.

The model is auto-downloaded on first run (~270 MB) to a local cache.
Progress is printed as JSON lines to stdout so the Dart sidecar manager
can relay it to the UI.
"""

import json
import os
import sys
import signal
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Globals ──────────────────────────────────────────────────────────────

MODEL_NAME = "nomic-ai/nomic-embed-text-v1.5"
PORT = 5055
model = None
model_ready = False
model_error = None

# Cache dir — follows XDG on Linux, ~/Library on macOS, AppData on Windows
def _cache_dir():
    if sys.platform == "darwin":
        return os.path.join(os.path.expanduser("~"), "Library", "Caches", "FrontPorchAI", "embeddings")
    elif sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
        return os.path.join(base, "FrontPorchAI", "Cache", "embeddings")
    else:
        xdg = os.environ.get("XDG_CACHE_HOME", os.path.join(os.path.expanduser("~"), ".cache"))
        return os.path.join(xdg, "front-porch-ai", "embeddings")


def _emit(event: str, **kwargs):
    """Print a JSON status line to stdout for the Dart sidecar to parse."""
    payload = {"event": event, **kwargs}
    print(json.dumps(payload), flush=True)


def _load_model():
    """Download (if needed) and load the embedding model."""
    global model, model_ready, model_error
    try:
        _emit("status", message="Importing sentence-transformers...")

        from sentence_transformers import SentenceTransformer

        cache = _cache_dir()
        os.makedirs(cache, exist_ok=True)
        os.environ["SENTENCE_TRANSFORMERS_HOME"] = cache

        _emit("status", message="Loading model (downloading if first run)...")

        # Use ONNX backend for CPU inference — no PyTorch needed at runtime
        model = SentenceTransformer(
            MODEL_NAME,
            trust_remote_code=True,
            backend="onnx",
            model_kwargs={"file_name": "onnx/model_quantized.onnx"},
        )

        # Warm up with a test embed
        _emit("status", message="Warming up model...")
        model.encode(["test"], prompt_name="search_document")

        model_ready = True
        _emit("ready", message="Embedding server ready", port=PORT)

    except Exception as e:
        model_error = str(e)
        _emit("error", message=f"Model load failed: {e}")


# ── HTTP Handler ─────────────────────────────────────────────────────────

class EmbedHandler(BaseHTTPRequestHandler):
    """Minimal HTTP handler for /v1/embeddings and /health."""

    def log_message(self, fmt, *args):
        """Suppress default access logs."""
        pass

    def _json_response(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json_response(200, {
                "status": "ok",
                "model_ready": model_ready,
                "model_error": model_error,
            })
        elif self.path == "/health/model":
            if model_ready:
                self._json_response(200, {"status": "ready"})
            elif model_error:
                self._json_response(503, {"status": "error", "error": model_error})
            else:
                self._json_response(503, {"status": "loading"})
        else:
            self._json_response(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/embeddings":
            self._json_response(404, {"error": "not found"})
            return

        if not model_ready:
            msg = model_error or "Model is still loading"
            self._json_response(503, {"error": msg})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            req = json.loads(raw)

            text_input = req.get("input", "")
            if isinstance(text_input, str):
                texts = [text_input]
            elif isinstance(text_input, list):
                texts = text_input
            else:
                self._json_response(400, {"error": "input must be string or array"})
                return

            # nomic-embed-text requires a task prefix
            embeddings = model.encode(
                texts,
                prompt_name="search_document",
                normalize_embeddings=True,
            )

            data = []
            for i, emb in enumerate(embeddings):
                data.append({
                    "object": "embedding",
                    "index": i,
                    "embedding": emb.tolist(),
                })

            self._json_response(200, {
                "object": "list",
                "data": data,
                "model": MODEL_NAME,
                "usage": {"prompt_tokens": 0, "total_tokens": 0},
            })

        except Exception as e:
            self._json_response(500, {"error": str(e)})


# ── Main ─────────────────────────────────────────────────────────────────

def main():
    _emit("status", message=f"Starting embedding server on port {PORT}...")

    # Start model loading in background so the HTTP server is responsive
    # for /health checks while the model downloads
    loader = threading.Thread(target=_load_model, daemon=True)
    loader.start()

    server = HTTPServer(("127.0.0.1", PORT), EmbedHandler)

    def shutdown(signum, frame):
        _emit("status", message="Shutting down...")
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    _emit("listening", port=PORT)
    server.serve_forever()


if __name__ == "__main__":
    main()
