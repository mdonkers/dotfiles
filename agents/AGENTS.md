# Personal instructions

## General

- Continue requested local edits, read-only investigation, and relevant checks until the task is complete. Make routine implementation choices from the available context; ask when missing information materially changes the outcome.
- Honor requests to propose changes or stop for review before editing.
- After a change, review affected comments and update or remove those that no longer make sense, including comments added earlier in the same task or PR.

## Git workflow

- By default, do repository work in a dedicated Git worktree on a new feature branch and create a PR for the completed changes.
- Read-only Git inspection requires no approval.
- Creating the worktree and feature branch, committing changes to that branch, pushing it with upstream tracking, and creating or updating its PR require no approval, including in new coding sessions.
- Before destructive Git operations, present the exact planned operations and obtain approval. This includes discarding uncommitted work, deleting branches or worktrees containing unmerged work, rewriting existing branch history, and force-pushing. Merging into an existing branch also requires approval. Approval covers the agreed operations; ask again if their scope changes.
- Keep commit subjects under 70 characters.
- Set `PINENTRY_USER_DATA=claudecode` for every commit so GPG signing works with pinentry.
- Push with upstream tracking, create the complete PR with a description using `gh`, and return its URL for inspection on GitHub.
- When creating a worktree, use the intended feature branch name immediately, without a `worktree-` prefix.

### Worktree location

- Create all new worktrees under `/Development/workspaces/<repo>/<branch>/`. Use this absolute path in Git commands. This is the single worktree root across repositories and coding agents. It keeps worktrees outside source checkouts and temporary directories, separate from Codex-managed storage and cleanup.
- Derive `<repo>` from the main checkout's directory name, even when starting from a linked worktree. Use `git rev-parse --path-format=absolute --git-common-dir` and `git worktree list --porcelain` to identify the repository and its main checkout. If unrelated repositories share a directory name, consistently qualify their folder names with the remote owner, such as `Dash0-dash0`.
- Use the exact branch name as the relative path beneath the repository folder, preserving `/` separators. For example, branch `fix/query-timeout` in `dash0` belongs at `/Development/workspaces/dash0/fix/query-timeout/`. Create parent directories as needed, then run `git -C <main-checkout> worktree add -b <branch> <absolute-worktree-path> <base-ref>`.
- Before creating anything, inspect `git worktree list --porcelain`. Reuse the worktree already assigned to the current task or branch, including one provided by Codex, rather than creating another. If its HEAD is detached, create the intended feature branch there before editing. Do not repurpose another task's worktree or overwrite an existing path. Resolve naming collisions with a descriptive branch suffix while keeping the same root.
- Do not create worktrees in `/tmp`, `$TMPDIR`, `~/.codex/worktrees`, inside a repository such as `.worktrees/`, or as ad hoc siblings of project checkouts. If the standard root is inaccessible, report the restriction and ask for an explicit alternative instead of silently choosing another location.
- For worktrees created by the Codex app before the agent runs, configure Settings > Worktrees > Worktree root to `/Development/workspaces`. AGENTS.md governs agent-created worktrees; it does not change the app setting or its generated directory layout. Reuse app-provided worktrees in place.
- Leave existing worktrees in place unless asked to consolidate them. Use `git worktree move` for an authorized move, and follow the approval rules above for destructive cleanup.

## Dash0 links

- Copy URLs returned by Dash0 MCP verbatim. Do not reconstruct or simplify their timestamps or URL encoding.
- When constructing UI deep links, use canonical UTC ISO timestamps with milliseconds for `from` and `to`, such as `2026-09-07T11:08:15.000Z`. Omitting `.000` fails Dash0's current deep-link validation.
- This timestamp requirement applies to UI deep links, not Prometheus API parameters.

## ClickHouse queries

- Connect as `claude_ch_analysis`, including when using `clickhouse-client --database otel`, unless connecting to a temporary server created via Docker. This account has an empty password.
- Before executing DDL, present the exact full statement and obtain approval. This includes `CREATE`, `DROP`, and `ALTER`, including temporary tables and tables using the `Memory` engine.
- When a table is needed to verify behavior, prefer a temporary table or the `Memory` engine after obtaining DDL approval.
