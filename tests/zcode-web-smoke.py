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
    refused_tokens = {}
    for name, token in {
        "unset": None,
        "empty": "",
        "ascii_whitespace": " \t\r\n\v\f",
        "unicode_whitespace": "\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff",
    }.items():
        denied_env = {**env}
        if token is not None:
            denied_env["ZCODE_SERVER_AUTH_TOKEN"] = token
        denied = subprocess.run(
            [package / "bin/zcode-web"], env=denied_env, capture_output=True, timeout=10
        )
        assert denied.returncode == 64 and b"ZCODE_SERVER_AUTH_TOKEN" in denied.stderr, name
        refused_tokens[name] = denied.returncode
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
    assert selection["options"]["reasoningLevel"], selection
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
                except (urllib.error.URLError, TimeoutError):
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
                "refused_tokens": refused_tokens,
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
