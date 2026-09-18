"""Opt-in live test of the installed helper, including its actual network transport."""
import json
import os
from pathlib import Path
import subprocess
import unittest


@unittest.skipUnless(os.environ.get("JEV_TEST_FILTER"), "Set JEV_TEST_FILTER to the built helper; uses the Jev API")
class LiveFilterTests(unittest.TestCase):
    def test_saved_key_over_environment_and_preserved_request(self):
        prompt = "Reply exactly BRIDGE_OK. Do not use tools or modify files.\n" + (
            "Thank you very much for your help and your time; I appreciate your assistance and I am grateful for the effort.\n" * 6
        )
        home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
        self.assertTrue((home / "jev-api-key").is_file(), "Requires an existing saved Settings key")
        request = {"id": 42, "method": "turn/start", "params": {
            "threadId": "fixture", "model": "fixture-model", "effort": "high", "input": [
                {"type": "text", "text": prompt}, {"type": "localImage", "path": "/tmp/fixture.png"}]}}
        env = dict(os.environ, TYPESAFE_API_KEY="invalid-environment-priority-test")
        result = subprocess.run([os.environ["JEV_TEST_FILTER"]], input=json.dumps(request),
                                text=True, capture_output=True, env=env, timeout=40, check=True)
        data = json.loads(result.stdout)
        updated = data["request"]
        text = updated["params"]["input"][0]["text"]
        self.assertIn("Reply exactly BRIDGE_OK. Do not use tools or modify files.", text)
        self.assertLess(len(text), len(prompt))
        updated["params"]["input"][0]["text"] = prompt
        self.assertEqual(updated, request)
        self.assertEqual(data["stats"]["apiCalls"], 2)
        self.assertGreater(data["stats"]["savedEstimate"], 0)


if __name__ == "__main__":
    unittest.main()
