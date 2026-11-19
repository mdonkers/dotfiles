# Personal instructions

## Working style

- Carry requested local edits, read-only investigation, and relevant checks through to completion. Make routine implementation choices from context; ask when missing information would change the outcome.
- When asked to propose changes or stop for review, stop before editing.
- After a change, update or remove the comments it made stale, including ones added earlier in the same task or PR.

## Git

### Approval

No approval needed, including in new sessions: read-only Git inspection; creating the task's worktree and feature branch; committing to that branch; pushing it with upstream tracking; creating or updating its PR; landed-PR cleanup.

Approval needed, after presenting the exact operations: discarding uncommitted work, deleting a branch or worktree that holds unmerged work, rewriting existing branch history, force-pushing, and merging into an existing branch. Approval covers the agreed operations; ask again when their scope changes.

### PR lifecycle

Implementation work is done when its PR is open for review: when I ask to implement, execute, or fix
something, run steps 1–3 without asking and return the PR URL, also when a skill's last step is "commit".

1. Work in a dedicated worktree on a new feature branch (see Worktrees).
2. Commit with `PINENTRY_USER_DATA=claudecode` set so GPG signing works with pinentry. Keep subjects under 70 characters.
3. Push with upstream tracking, create the PR with a complete description using `gh`, and return its URL.
4. When the PR is landed (merged, or queued in a merge queue), read `~/dotfiles/agents/pr-cleanup.md` and follow it to remove the local worktree and branch.

### Worktrees

- Every worktree lives directly under `/Development/workspaces/` at `<repo>-<branch-slug>/`, for every repository and agent. Use this absolute path in Git commands.
- `<repo>` is the main checkout's directory name, even from a linked worktree; find the main checkout with `git rev-parse --path-format=absolute --git-common-dir` and `git worktree list --porcelain`. When unrelated repositories share a name, qualify it with the remote owner, such as `Dash0-dash0`.
- `<branch-slug>` is the branch name with `/` replaced by `-`; the Git branch keeps its name. Name the branch as intended from the start, without a `worktree-` prefix. Example: `fix/query-timeout` in `dash0` lives at `/Development/workspaces/dash0-fix-query-timeout/`.
- Before creating, inspect `git worktree list --porcelain` and reuse the worktree already assigned to this task or branch, including one the Codex app created. On a detached HEAD, create the feature branch there before editing.
- Create with `git -C <main-checkout> worktree add -b <branch> <absolute-worktree-path> <base-ref>`, creating the root as needed. Resolve a path collision with a descriptive branch suffix under the same root; other tasks' worktrees and existing paths stay as they are.
- `/Development/workspaces` is the only worktree root: never `/tmp`, `$TMPDIR`, `~/.codex/worktrees`, a repository-internal directory such as `.worktrees/`, or a sibling of a project checkout. If the root is inaccessible, report it and ask for an alternative.
- Apart from landed-PR cleanup, existing worktrees stay in place unless I ask to consolidate them; move them with `git worktree move`.

## Dash0 links

- Copy URLs returned by Dash0 MCP verbatim, timestamps and URL encoding included.
- In UI deep links you construct, write `from` and `to` as UTC ISO timestamps with milliseconds, such as `2026-09-07T11:08:15.000Z`; Dash0 rejects them without `.000`. Prometheus API parameters keep their own format.

## ClickHouse queries

- Connect as `claude_ch_analysis` (empty password), including with `clickhouse-client --database otel`. Temporary servers created via Docker are the exception.
- Before any DDL (`CREATE`, `DROP`, `ALTER`, including on temporary and `Memory` tables), present the exact full statement and get approval.
- To verify behavior with a table, prefer a temporary or `Memory` table.

## Agent skills (dash0 repo only)

Applies only in `dash0hq/dash0`: the main checkout `/Development/projects/Dash0/dash0` and its worktrees under `/Development/workspaces/dash0-*`.

### Issue tracker

Issues live in Linear, team BPE (Eng Backend Platform), via the Linear MCP; GitHub Issues is disabled. See `~/.claude/mattpocock-skills/dash0/issue-tracker.md`.

### Triage labels

Triage roles map onto BPE's existing workflow states; no custom labels. See `~/.claude/mattpocock-skills/dash0/triage-labels.md`.

### Domain docs

Multi-context and read-only: existing glossaries and ADR folders are listed; propose new terms and ADRs instead of writing them. See `~/.claude/mattpocock-skills/dash0/domain.md`.
