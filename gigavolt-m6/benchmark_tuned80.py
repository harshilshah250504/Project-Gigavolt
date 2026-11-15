import os
import json
import runpy
import sys
import urllib.request
from pathlib import Path
from unittest.mock import patch

original_open = urllib.request.urlopen


def open_with_token_cap(request, *args, **kwargs):
    if (
        isinstance(request, urllib.request.Request)
        and request.full_url == os.environ.get("GIGAVOLT_OLLAMA_CHAT_URL", "http://127.0.0.1:11434/api/chat")
        and request.data
    ):
        payload = json.loads(request.data)
        if payload.get("options", {}).get("num_predict") == 100:
            payload["options"]["num_predict"] = 80
            request.data = json.dumps(payload).encode()
    return original_open(request, *args, **kwargs)


script = Path(__file__).with_name("benchmark_m6.py")
sys.argv = [str(script), "tuned80"]
with patch.object(urllib.request, "urlopen", open_with_token_cap):
    runpy.run_path(str(script), run_name="__main__")
