# Landed-PR cleanup

A PR is **landed** when it is merged, or open and queued in a GitHub merge queue. Cleaning up a landed PR's local worktree and local branch needs no approval. Every other PR is unmerged work and falls under the approval rules in `AGENTS.md`: an open PR that is not queued (auto-merge enabled but not yet queued counts as not queued), and a closed unmerged PR.

1. Check the PR. `gh pr view --json` has no merge-queue field; use GraphQL:
   `gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){state isInMergeQueue headRefOid}}}' -F o=<owner> -F r=<repo> -F n=<pr>`
   Landed means `state` is `MERGED`, or `state` is `OPEN` with `isInMergeQueue: true`.
2. Confirm the worktree is clean (no uncommitted or untracked files) and the local branch tip equals `headRefOid`. If either differs, report the difference and ask.
3. From the main checkout, run `git -C <main-checkout> worktree remove <absolute-worktree-path>`, then `git -C <main-checkout> branch -D <branch>`. `-D` is needed because squashed or queued commits are not in the local base branch.

Done when the worktree path and the local branch are both gone, and the remote branch is untouched.

The remote branch belongs to GitHub: deleting a queued PR's remote branch closes the PR and drops it from the queue, and GitHub deletes merged branches itself. If the queue later rejects the PR, restore the branch with `git fetch origin <branch>` and a new worktree.
