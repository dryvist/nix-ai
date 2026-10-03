"""Exercise the installed native HTTP entry point with an isolated home."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

package = Path(sys.argv[1])
artifacts = Path(sys.argv[2])
artifacts.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as home:
    env = {**os.environ, "HOME": home, "ZCODE_ENV": "production"}
    env.pop("ZCODE_SERVER_AUTH_TOKEN", None)
    denied = subprocess.run([package / "bin/zcode-web"], env=env, capture_output=True)
    assert denied.returncode != 0 and b"ZCODE_SERVER_AUTH_TOKEN" in denied.stderr
    subprocess.run([package / "bin/zcode", "--version"], env=env, check=True)
    subprocess.run(
        [package / "bin/zcode-configure-key"],
        env={**env, "ZAI_API_KEY": "offline-package-smoke-key"},
        check=True,
    )
    configs = list(Path(home).rglob("provider_config.json"))
    assert len(configs) == 1, "Native key initializer wrote no unique configuration"
    selection = json.loads(configs[0].read_text())["config"]["defaultModelSelection"]
    assert selection["modelId"] == sys.argv[3], selection
    env.update(ZCODE_SERVER_AUTH_TOKEN="offline-smoke-token", PORT="3039")
    with (artifacts / "server.log").open("w") as log:
        server = subprocess.Popen([package / "bin/zcode-web"], env=env, stdout=log, stderr=log)
        try:
            base = "http://127.0.0.1:3039"
            for attempt in range(100):
                assert server.poll() is None, "Server exited before listening"
                try:
                    urllib.request.urlopen(base + "/api/server-info", timeout=1)
                except urllib.error.HTTPError as error:
                    assert error.code == 401
                    break
                except urllib.error.URLError:
                    time.sleep(0.1)
            else:
                raise AssertionError("Server did not listen")
            with urllib.request.urlopen(base + "/api/server-info?token=offline-smoke-token") as response:
                assert response.status == 200
                assert "HttpOnly" in response.headers["Set-Cookie"]
                info = json.load(response)
            with urllib.request.urlopen(base + "/") as response:
                html = response.read().decode()
                assert response.status == 200 and '<div id="root">' in html
                assert "/assets/" in html
            (artifacts / "result.json").write_text(json.dumps({
                "missing_token_refused": True,
                "unauthorized_status": 401,
                "authorized_status": 200,
                "native_ui": True,
                "native_key_initialized": True,
                "model_selection": selection,
                "server_info": info,
            }, indent=2) + "\n")
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
