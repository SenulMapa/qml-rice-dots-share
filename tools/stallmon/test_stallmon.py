#!/usr/bin/env python3
"""Tests for stallmon. Run: python3 -I tools/stallmon/test_stallmon.py"""
import json
import os
import sys
import tempfile
import unittest

# -I drops the script directory from sys.path, so add it explicitly.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import stallmon  # noqa: E402


class FormatEventTest(unittest.TestCase):
    def test_event_line_schema(self):
        top = [{"pid": 1, "comm": "x", "cpu_pct": 1.5, "rss_mb": 2.0,
                "io_read_kb": 3.0, "io_write_kb": 4.0}]
        line = stallmon.format_event("memory", 300, top)
        self.assertTrue(line.endswith("\n"))
        self.assertEqual(line.count("\n"), 1)
        obj = json.loads(line)
        self.assertEqual(set(obj.keys()), {"ts", "kind", "stall_ms", "top"})
        self.assertEqual(obj["kind"], "memory")
        self.assertEqual(obj["stall_ms"], 300)
        self.assertEqual(obj["top"], top)
        self.assertIsInstance(obj["ts"], str)


class AppendEventTest(unittest.TestCase):
    def test_rotation_at_5mb(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "stalls.jsonl")
            # Fill the file to exactly the limit.
            with open(path, "wb") as f:
                f.write(b"a" * 5_000_000)
            stallmon.append_event(path, "new\n", max_bytes=5_000_000)
            self.assertTrue(os.path.exists(path + ".1"))
            with open(path + ".1", "rb") as f:
                self.assertEqual(len(f.read()), 5_000_000)
            with open(path, "r") as f:
                self.assertEqual(f.read(), "new\n")

    def test_no_rotation_below_limit(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "stalls.jsonl")
            stallmon.append_event(path, "one\n", max_bytes=5_000_000)
            stallmon.append_event(path, "two\n", max_bytes=5_000_000)
            self.assertFalse(os.path.exists(path + ".1"))
            with open(path) as f:
                self.assertEqual(f.read(), "one\ntwo\n")


class DeltaTriggerTest(unittest.TestCase):
    def test_fallback_delta(self):
        self.assertTrue(stallmon.delta_trigger(0, 300_000, threshold_ms=250))
        self.assertFalse(stallmon.delta_trigger(0, 200_000, threshold_ms=250))

    def test_exact_threshold_fires(self):
        self.assertTrue(stallmon.delta_trigger(1_000_000, 1_250_000))


class TopProcsTest(unittest.TestCase):
    def test_top_procs_shape(self):
        procs = stallmon.top_procs(n=5, window=0.05)
        self.assertLessEqual(len(procs), 5)
        for p in procs:
            self.assertEqual(
                set(p.keys()),
                {"pid", "comm", "cpu_pct", "rss_mb", "io_read_kb", "io_write_kb"},
            )


class TriggerSpecTest(unittest.TestCase):
    def test_trigger_bytes_are_nul_terminated_250ms_in_2s(self):
        self.assertEqual(stallmon.trigger_spec(), b"some 250000 2000000\x00")

    def test_window_is_multiple_of_2s(self):
        self.assertEqual(stallmon.TRIGGER_WINDOW_US % 2_000_000, 0)


class ElapsedDeltaTest(unittest.TestCase):
    def test_threshold_scales_with_elapsed(self):
        self.assertFalse(stallmon.delta_trigger(0, 400_000, elapsed_s=2.0))
        self.assertTrue(stallmon.delta_trigger(0, 500_000, elapsed_s=2.0))


class PollClassifyTest(unittest.TestCase):
    def test_pollpri_is_stall(self):
        self.assertEqual(stallmon.classify_poll_event(stallmon.select.POLLPRI), "stall")

    def test_error_without_pri_is_dead(self):
        for flag in (stallmon.select.POLLERR, stallmon.select.POLLNVAL):
            self.assertEqual(stallmon.classify_poll_event(flag), "dead")

    def test_pri_with_err_is_stall(self):
        ev = stallmon.select.POLLPRI | stallmon.select.POLLERR
        self.assertEqual(stallmon.classify_poll_event(ev), "stall")


class RecordSafelyTest(unittest.TestCase):
    def test_unwritable_path_does_not_raise(self):
        with tempfile.TemporaryDirectory() as d:
            blocker = os.path.join(d, "file")
            with open(blocker, "w"):
                pass
            bad = os.path.join(blocker, "stalls.jsonl")  # parent is a file
            stallmon.record_events(bad, [("cpu", 300)], [])  # must not raise
            good = os.path.join(d, "stalls.jsonl")
            stallmon.record_events(good, [("cpu", 300)], [])
            with open(good) as f:
                self.assertEqual(json.loads(f.readline())["kind"], "cpu")


class OpenTriggersTest(unittest.TestCase):
    def test_open_writes_nul_terminated_spec_to_each_resource(self):
        writes = []
        real_open, real_write, real_close = os.open, os.write, os.close
        opened = []

        def fake_open(path, flags):
            fd = 1000 + len(opened)
            opened.append((fd, path))
            return fd

        def fake_write(fd, data):
            writes.append((fd, data))
            return len(data)

        stallmon.os.open, stallmon.os.write, stallmon.os.close = (
            fake_open, fake_write, lambda fd: None)
        try:
            fds = stallmon._open_triggers()
        finally:
            stallmon.os.open, stallmon.os.write, stallmon.os.close = (
                real_open, real_write, real_close)
        self.assertEqual(sorted(fds.values()), sorted(stallmon.KINDS))
        self.assertEqual(len(writes), 3)
        for _, data in writes:
            self.assertEqual(data, b"some 250000 2000000\x00")


if __name__ == "__main__":
    unittest.main()
