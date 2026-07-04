#!/usr/bin/env bash
# exloom — list the task worktrees created for parallel execution, with their
# branch and short HEAD, so the controller can see what is still live.
#
# Usage: list-task-worktrees.sh

set -euo pipefail

path=""; head=""
any=0
while IFS= read -r line; do
  case "$line" in
    worktree\ *) path="${line#worktree }" ;;
    HEAD\ *)     head="${line#HEAD }" ;;
    branch\ *)
      branch="${line#branch refs/heads/}"
      case "$branch" in
        task/*) printf '%s\t%s\t%s\n' "$branch" "${head:0:7}" "$path"; any=1 ;;
      esac
      ;;
  esac
done < <(git worktree list --porcelain)

[ "$any" -eq 1 ] || echo "(no task worktrees)"
