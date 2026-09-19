"""Opt-in live test of the installed helper, including its actual network transport."""

import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest


@unittest.skipUnless(
    os.environ.get("JEV_TEST_FILTER"),
    "Set JEV_TEST_FILTER to the built helper; uses the Jev API",
)
class LiveFilterTests(unittest.TestCase):
    def test_saved_key_over_environment_and_preserved_request(self):
        prompt = 'Please explain this exact code without modifying it: `print("hello world")`. Thanks very much for your time and assistance.'
        home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
        self.assertTrue(
            (home / "jev-api-key").is_file(), "Requires an existing saved Settings key"
        )
        request = {
            "id": 42,
            "method": "turn/start",
            "params": {
                "threadId": "fixture",
                "model": "fixture-model",
                "effort": "high",
                "input": [
                    {"type": "text", "text": prompt},
                    {"type": "localImage", "path": "/tmp/fixture.png"},
                ],
            },
        }
        temporary = tempfile.TemporaryDirectory(prefix="jev-live-filter-")
        self.addCleanup(temporary.cleanup)
        isolated_home = Path(temporary.name)
        shutil.copyfile(home / "jev-api-key", isolated_home / "jev-api-key")
        (isolated_home / "jev-api-key").chmod(0o600)
        (isolated_home / "jev-message-settings.json").write_text(
            json.dumps({"enabled": True, "mode": "strict"})
        )
        env = dict(
            os.environ,
            CODEX_HOME=temporary.name,
            TYPESAFE_API_KEY="invalid-environment-priority-test",
        )
        result = subprocess.run(
            [os.environ["JEV_TEST_FILTER"]],
            input=json.dumps(request),
            text=True,
            capture_output=True,
            env=env,
            timeout=90,
            check=True,
        )
        data = json.loads(result.stdout)
        updated = data["request"]
        text = updated["params"]["input"][0]["text"]
        self.assertIn('`print("hello world")`', text)
        self.assertIn("without modifying", text)
        self.assertLess(len(text), len(prompt), data["stats"])
        updated["params"]["input"][0]["text"] = prompt
        self.assertEqual(updated, request)
        self.assertGreaterEqual(data["stats"]["apiCalls"], 2)
        self.assertGreater(data["stats"]["savedEstimate"], 0)


if __name__ == "__main__":
    unittest.main()
