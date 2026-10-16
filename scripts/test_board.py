#!/usr/bin/env python3
"""Offline board coordination regressions; never commits or contacts origin."""
import argparse
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import board


class CoordinationTest(unittest.TestCase):
    def test_handoffs(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.object(board, "TASKS", Path(directory)), patch.object(
            board, "publish", side_effect=lambda message, mutate: mutate()
        ):
            path = board.task_path("1")
            meta = dict(id="T-001", title="Work", status="claimed", owner="alice", scope="", depends="", updated=board.now())
            board.write_task(path, meta, "## Log\n")
            args = argparse.Namespace(agent="bob", id="1", steal=True)
            with self.assertRaises(board.BoardError):
                board.transition(args, "claimed", "claimed", False)
            meta["updated"] = "2000-01-01T00:00Z"
            board.write_task(path, meta, "## Log\n")
            board.transition(args, None, "note: hello", False)
            self.assertEqual(board.read_task(path)[0]["updated"], meta["updated"])
            with self.assertRaises(board.BoardError):
                board.transition(args, "done", "done", True)
            board.transition(args, "claimed", "claimed", False)
            self.assertEqual(board.read_task(path)[0]["owner"], "bob")
            meta.update(status="open", owner="", depends="T-002")
            board.write_task(path, meta, "## Log\n")
            with self.assertRaises(board.BoardError):
                board.transition(args, "claimed", "claimed", False)
            dependency = dict(meta, id="T-002", status="done", depends="")
            board.write_task(board.task_path("2"), dependency, "## Log\n")
            board.transition(args, "claimed", "claimed", False)
            meta.update(title="Human: playtest", depends="")
            board.write_task(path, meta, "## Log\n")
            with self.assertRaises(board.BoardError):
                board.transition(args, "claimed", "claimed", False)
            args.agent = "human:theo"
            self.assertEqual(board.need_agent(args), "human:theo")
            board.transition(args, "claimed", "claimed", False)


if __name__ == "__main__":
    unittest.main()
