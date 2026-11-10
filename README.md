## dotfiles

**To install:**

```console
$ make
```

This will create symlinks from this repo to your home folder.

Personal agent instructions live in `agents/AGENTS.md`. `make dotfiles` links
`~/.codex/AGENTS.md` to this file and `~/.claude/CLAUDE.md` to the Codex path,
so both agents read the same instructions. Codex reads global instructions
from `~/.codex` by default, rather than `~/.agents`.

**To customize / detailed guidelines:**

Look at the file `debian_install.md`

#### Thx

Big thanks to Jessie Frazelle of which this repo is largely (or at least started as) a copy.
The original repo can be found here; [https://github.com/jfrazelle/dotfiles](https://github.com/jfrazelle/dotfiles).

Also many thanks to the great Arch Linux wiki pages which contain many valuable resources.


### Agent cleanup

`agent_cleanup` previews Codex and Claude Code data eligible for removal.
`agent_cleanup --apply` deletes it. Reload `~/.functions` after updating the
dotfiles. The executable is also available as `agent-cleanup` after `make bin`.
Requires Linux and Python 3.11 or newer; no extra Python packages are needed.
Close interactive Codex and Claude clients before applying.

- Sessions qualify only when their latest activity is older than one calendar
  month. Codex checks transcript timestamps, mtimes and database activity, protects parents
  with recent descendants, and uses `codex delete <uuid> --force` for deletion.
- Claude checks transcript timestamps, session indexes, command history and
  related files. It removes old transcripts, subagents, file history, session
  environments, tasks, todos and session-specific debug files, then removes
  their index/history entries and stale last-session references. Newer sessions
  in the same project and project memory are retained.
- Native Codex standalone/daemon packages and Claude binaries keep the two
  newest usable installed versions. Versions referenced by launchers, `current`
  selections or running processes are also retained. Incomplete downloads and
  unrecognized version names are skipped.

The command honors `CODEX_HOME`, the base Codex config's `sqlite_home`,
`CLAUDE_CONFIG_DIR` and XDG data/cache locations. It does not prune plugin caches,
package-manager installations, Git worktrees, settings, credentials or general
logs/backups. This is local storage cleanup, not guaranteed erasure of every
copy or reference. Claude has no per-session purge command in the inspected
version, so its cleanup targets the known local storage layout. Unexpected
formats stop cleanup instead of guessing.

Run the cleanup regression checks with:

```console
python3 -m unittest discover -s tests -p 'test_agent_cleanup.py'
```
