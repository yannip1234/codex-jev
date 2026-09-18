import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest

BRIDGE = Path(__file__).with_name("codex-jev-bridge.py")


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        backend = self.root / "backend"
        backend.write_text("""#!/usr/bin/python3
import json,sys
if '--version' in sys.argv:
 print('fake-version');sys.exit(0)
for line in sys.stdin:
 r=json.loads(line)
 if r.get('method')=='die':sys.exit(7)
 print(json.dumps(r),flush=True)
""")
        helper = self.root / "filter"
        helper.write_text("""#!/usr/bin/python3
import json,sys,time
r=json.load(sys.stdin)
if r['params']['input'][0]['text']=='slow':time.sleep(.15)
if r['params']['input'][0]['text']=='fail':sys.exit(2)
r['params']['input'][0]['text']='shortened'
print(json.dumps({'request':r,'stats':{'apiCalls':2,'savedEstimate':20,'status':'test'}}))
""")
        backend.chmod(0o700)
        helper.chmod(0o700)
        self.env = dict(
            os.environ,
            JEV_REAL_CODEX=str(backend),
            JEV_MESSAGE_FILTER=str(helper),
            CODEX_HOME=str(self.root),
        )
        self.proc = subprocess.Popen(
            [sys.executable, str(BRIDGE), "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            env=self.env,
            bufsize=0,
        )

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        self.proc.stdin.close()
        self.proc.stdout.close()
        self.temp.cleanup()

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj).encode() + b"\n")
        self.proc.stdin.flush()

    def read(self):
        self.assertTrue(
            select.select([self.proc.stdout], [], [], 5)[0], "bridge stalled"
        )
        return json.loads(self.proc.stdout.readline())

    def turn(self, method="turn/start", text="original", id=1):
        return {
            "id": id,
            "method": method,
            "params": {
                "threadId": "thread-a",
                "model": "model-test",
                "input": [
                    {"type": "text", "text": text, "text_elements": []},
                    {"type": "localImage", "path": "/tmp/image.png"},
                ],
            },
        }

    def test_start_and_steer_filter_only_message_preserving_attachments(self):
        for method in ["turn/start", "turn/steer"]:
            request = self.turn(method)
            self.send(request)
            result = self.read()
            request["params"]["input"][0]["text"] = "shortened"
            self.assertEqual(result, request)

    def test_failure_forwards_original(self):
        request = self.turn(text="fail")
        self.send(request)
        self.assertEqual(self.read(), request)

    def test_responses_bypass_filter_but_same_thread_requests_stay_ordered(self):
        self.send(self.turn(text="slow"))
        later = {
            "id": 2,
            "method": "turn/interrupt",
            "params": {"threadId": "thread-a", "turnId": "turn-a"},
        }
        response = {"id": "approval-id", "result": {"decision": "accept"}}
        self.send(later)
        self.send(response)
        self.assertEqual(self.read(), response)
        self.assertEqual(self.read()["id"], 1)
        self.assertEqual(self.read(), later)

    def test_backend_exit_reaches_client(self):
        self.send({"id": 1, "method": "die"})
        self.assertEqual(self.proc.wait(timeout=5), 7)

    def test_non_server_arguments_pass_through(self):
        result = subprocess.run(
            [sys.executable, str(BRIDGE), "--version"],
            env=self.env,
            capture_output=True,
            check=True,
        )
        self.assertEqual(result.stdout, b"fake-version\n")


if __name__ == "__main__":
    unittest.main()
