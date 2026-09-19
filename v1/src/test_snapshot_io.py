"""Regression tests for status snapshots briefly absent or incomplete on the bind mount."""
from pathlib import Path
import json
import tempfile
import threading
import time
import unittest
import atomic_io

ROOT = Path(__file__).resolve().parents[1]


class SnapshotReads(unittest.TestCase):
    def reader(self):
        reader = getattr(atomic_io, "read_json", None)
        self.assertTrue(callable(reader), "Status readers must recover from a briefly unavailable snapshot")
        return reader

    def temporary(self):
        directory = tempfile.TemporaryDirectory(prefix="snapshot_test_", dir=ROOT / "review")
        self.assertTrue(Path(directory.name).resolve().is_relative_to(ROOT.resolve()))
        self.addCleanup(directory.cleanup)
        return Path(directory.name) / "state.json"

    def test_absent_then_published_snapshot_is_read(self):
        read = self.reader(); path = self.temporary()
        worker = threading.Thread(target=lambda: (time.sleep(.05), path.write_text('{"passed": 23}', encoding="utf-8")))
        worker.start()
        try:
            self.assertEqual(read(path, wait_seconds=1), {"passed": 23})
        finally:
            worker.join()

    def test_partial_snapshot_then_valid_is_read(self):
        read = self.reader(); path = self.temporary()
        path.write_text('{"passed":', encoding="utf-8")
        worker = threading.Thread(target=lambda: (time.sleep(.05), path.write_text('{"passed": 30}', encoding="utf-8")))
        worker.start()
        try:
            self.assertEqual(read(path, wait_seconds=1), {"passed": 30})
        finally:
            worker.join()

    def test_optional_absent_snapshot_cannot_mean_finished(self):
        read = self.reader()
        self.assertIsNone(read(self.temporary(), wait_seconds=.05, missing_ok=True))

    def test_persistently_corrupt_snapshot_is_not_hidden(self):
        read = self.reader(); path = self.temporary()
        path.write_text('{"passed":', encoding="utf-8")
        with self.assertRaises(json.JSONDecodeError):
            read(path, wait_seconds=.05, missing_ok=True)


if __name__ == "__main__":
    unittest.main()
