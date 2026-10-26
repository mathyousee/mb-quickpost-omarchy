import concurrent.futures
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "microblog-drafts"


class DraftTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name)
        self.environment = dict(os.environ, XDG_STATE_HOME=str(self.state))
        self.path = self.state / "microblog/drafts.json"

    def request(self, action, **fields):
        result = subprocess.run(
            [str(HELPER)],
            input=json.dumps({"action": action, **fields}),
            text=True, capture_output=True, env=self.environment, check=True,
        )
        return json.loads(result.stdout)

    def test_persist_update_and_delete_with_private_permissions(self):
        text = "Line one & café\nLine two\n\n"
        self.assertEqual(self.request("list")["drafts"], [])
        saved = self.request("stash", text=text)
        draft_id = saved["id"]
        self.assertEqual(self.request("list")["drafts"][0]["text"], text)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.path.parent / ".lock").stat().st_mode), 0o600)
        updated = self.request("stash", id=draft_id, text="Updated")
        self.assertEqual(len(updated["drafts"]), 1)
        self.assertEqual(updated["drafts"][0]["id"], draft_id)
        self.assertEqual(updated["drafts"][0]["text"], "Updated")
        self.assertEqual(self.request("delete", id=draft_id)["drafts"], [])

    def test_corrupt_store_is_not_overwritten(self):
        self.request("stash", text="Keep me")
        for corrupt in ('[{"text":"missing fields"}]', "{broken json"):
            with self.subTest(corrupt=corrupt):
                self.path.write_text(corrupt)
                with self.assertRaises(subprocess.CalledProcessError):
                    self.request("stash", text="New note")
                self.assertEqual(self.path.read_text(), corrupt)

    def test_rejected_actions_preserve_saved_drafts(self):
        saved = self.request("stash", text="Keep me")
        for action, fields in (
            ("stash", {"text": " \n\t"}),
            ("stash", {"id": "missing", "text": "New note"}),
            ("delete", {"id": "missing"}),
        ):
            with self.subTest(action=action, fields=fields):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.request(action, **fields)
        self.assertEqual(self.request("list")["drafts"], saved["drafts"])

    def test_failed_atomic_replace_preserves_previous_contents(self):
        import runpy
        from unittest import mock

        self.request("stash", text="Keep me")
        original = self.path.read_bytes()
        save = runpy.run_path(str(HELPER))["save"]
        with mock.patch("os.replace", side_effect=OSError("test write failure")):
            with self.assertRaises(OSError):
                save(self.path, [])
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(self.path.parent.glob(".drafts-*")), [])

    def test_concurrent_saves_do_not_lose_drafts(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda i: self.request("stash", text=f"Note {i}"), range(8)))
        drafts = self.request("list")["drafts"]
        self.assertEqual({draft["text"] for draft in drafts}, {f"Note {i}" for i in range(8)})


if __name__ == "__main__":
    unittest.main()
