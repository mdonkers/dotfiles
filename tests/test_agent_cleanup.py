"""Run with python3 -m unittest discover -s tests -p 'test_agent_cleanup.py'."""

import contextlib
import datetime as dt
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import uuid


loader = importlib.machinery.SourceFileLoader(
    'agent_cleanup', str(Path(__file__).resolve().parents[1] / 'bin/agent-cleanup'))
cleanup = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(cleanup)
OLD = dt.datetime(2020, 1, 1, tzinfo=dt.timezone.utc).timestamp()
RECENT = dt.datetime.now(dt.timezone.utc).timestamp()


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, path, data, when=OLD):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data) + '\n')
        os.utime(path, (when, when))
        return path

    def codex(self, sid, parent=None, when=OLD):
        return self.write(self.root / 'sessions' / (sid + '.jsonl'),
                          {'payload': {'id': sid, 'parent_thread_id': parent}}, when)

    def test_calendar_month_clamps_month_end_and_crosses_year(self):
        self.assertEqual(cleanup.month_ago(dt.datetime(2024, 3, 31)), dt.datetime(2024, 2, 29))
        self.assertEqual(cleanup.month_ago(dt.datetime(2025, 1, 10)), dt.datetime(2024, 12, 10))

    def test_old_parent_with_recent_descendant_is_kept(self):
        parent, child, old = [str(uuid.uuid4()) for _ in range(3)]
        self.codex(parent)
        self.codex(child, parent, RECENT)
        self.codex(old)
        self.assertEqual(cleanup.codex_sessions(self.root, RECENT - 100), [old])

    def test_codex_recorded_activity_protects_restored_transcript(self):
        sid = str(uuid.uuid4())
        path = self.codex(sid)
        with path.open('a') as stream:
            stream.write(json.dumps({'timestamp': dt.datetime.now(dt.timezone.utc).isoformat()}) + '\n')
        os.utime(path, (OLD, OLD))
        self.assertEqual(cleanup.codex_sessions(self.root, RECENT - 100), [])

    def test_archived_codex_session_is_included(self):
        sid = str(uuid.uuid4())
        self.write(self.root / 'archived_sessions' / (sid + '.jsonl'), {'payload': {'id': sid}})
        self.assertEqual(cleanup.codex_sessions(self.root, RECENT - 100), [sid])

    def test_old_tree_deleted_once_via_parent(self):
        parent, child = [str(uuid.uuid4()) for _ in range(2)]
        self.codex(parent)
        self.codex(child, parent)
        self.assertEqual(cleanup.codex_sessions(self.root, RECENT - 100), [parent])

    def test_database_activity_protects_old_transcript(self):
        sid = str(uuid.uuid4())
        self.codex(sid)
        with sqlite3.connect(self.root / 'state_5.sqlite') as db:
            db.execute('CREATE TABLE threads (id TEXT, updated_at INTEGER)')
            db.execute('INSERT INTO threads VALUES (?, ?)', (sid, int(RECENT)))
        self.assertEqual(cleanup.codex_sessions(self.root, RECENT - 100), [])

    def test_claude_recent_sidecar_and_history_protect_sessions(self):
        sidecar, history, old = [str(uuid.uuid4()) for _ in range(3)]
        for sid in (sidecar, history, old):
            self.write(self.root / 'projects/proj' / (sid + '.jsonl'), {'sessionId': sid})
        side = self.write(self.root / 'projects/proj' / sidecar / 'subagents/a.jsonl', {}, RECENT)
        self.write(self.root / 'history.jsonl', {'sessionId': history, 'timestamp': RECENT * 1000})
        found, *_ = cleanup.claude_sessions(self.root, RECENT - 100)
        self.assertEqual(set(found), {old})
        self.assertTrue(side.exists())

    def test_claude_recorded_timestamp_protects_restored_file(self):
        sid = str(uuid.uuid4())
        self.write(self.root / 'projects/proj' / (sid + '.jsonl'),
                   {'timestamp': dt.datetime.now(dt.timezone.utc).isoformat()})
        self.assertEqual(cleanup.claude_sessions(self.root, RECENT - 100)[0], {})

    def test_two_usable_versions_kept_with_active_rollback(self):
        versions = self.root / 'versions'
        for name in ['2.1.9', '2.1.10', '2.1.11', '2.1.12']:
            path = self.write(versions / name, {})
            path.chmod(0o755)
        (versions / '2.1.13').touch()  # interrupted download
        found = cleanup.versions(versions, None, {(versions / '2.1.9').resolve()})
        self.assertEqual(found, [versions / '2.1.10'])

    def test_symlinked_sidecar_stops_cleanup(self):
        sid = str(uuid.uuid4())
        self.write(self.root / 'projects/proj' / (sid + '.jsonl'), {})
        (self.root / 'file-history').mkdir()
        (self.root / 'file-history' / sid).symlink_to(self.root / 'projects', target_is_directory=True)
        with self.assertRaises(ValueError):
            cleanup.claude_sessions(self.root, RECENT - 100)

    def test_apply_removes_old_claude_assets_and_references_only(self):
        claude = self.root / '.claude'
        codex = self.root / '.codex'
        old, recent = [str(uuid.uuid4()) for _ in range(2)]
        old_path = self.write(claude / 'projects/proj' / (old + '.jsonl'), {'sessionId': old})
        recent_path = self.write(claude / 'projects/proj' / (recent + '.jsonl'), {}, RECENT)
        side = self.write(claude / 'file-history' / old / 'backup', {})
        os.utime(side.parent, (OLD, OLD))
        memory = self.write(claude / 'projects/proj/memory/MEMORY.md', {'keep': True})
        history = claude / 'history.jsonl'
        history.write_text(json.dumps({'sessionId': old}) + '\n' + json.dumps({'sessionId': recent}) + '\n')
        history.chmod(0o600)
        index = self.write(claude / 'projects/proj/sessions-index.json',
                           {'entries': [{'sessionId': old}, {'sessionId': recent}]})
        config = self.write(claude / '.claude.json', {'projects': {'proj': {
            'lastSessionId': old, 'lastSessionMetrics': {'tokens': 123}, 'allowedTools': ['Read']}}})
        env = {'HOME': str(self.root), 'CODEX_HOME': str(codex), 'CLAUDE_CONFIG_DIR': str(claude),
               'XDG_DATA_HOME': str(self.root / 'share')}
        with patch.dict(os.environ, env), patch.object(cleanup, 'running_processes', return_value=(set(), [])):
            with contextlib.redirect_stdout(io.StringIO()):
                cleanup.run(False)
                self.assertTrue(old_path.exists(), 'dry run must not delete')
                cleanup.run(True)
        self.assertFalse(old_path.exists())
        self.assertFalse(side.exists())
        self.assertTrue(recent_path.exists())
        self.assertTrue(memory.exists())
        self.assertEqual(cleanup.json_lines(history), [{'sessionId': recent}])
        self.assertEqual(history.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(index.read_text())['entries'], [{'sessionId': recent}])
        self.assertEqual(json.loads(config.read_text())['projects']['proj'], {'allowedTools': ['Read']})

    def test_apply_refuses_while_interactive_clients_run(self):
        with patch.object(cleanup, 'running_processes', return_value=(set(), ['1234'])):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError):
                cleanup.run(True)

    def test_codex_deletion_uses_supported_cli(self):
        sid = str(uuid.uuid4())
        self.codex(sid)
        env = {'HOME': str(self.root), 'CODEX_HOME': str(self.root),
               'CLAUDE_CONFIG_DIR': str(self.root / '.claude'), 'XDG_DATA_HOME': str(self.root / 'share')}
        with patch.dict(os.environ, env), patch.object(cleanup, 'running_processes', return_value=(set(), [])):
            with patch.object(cleanup.subprocess, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
                cleanup.run(True)
        self.assertEqual(run.call_args_list[-1].args[0][-3:], ['delete', sid, '--force'])


if __name__ == '__main__':
    unittest.main()
