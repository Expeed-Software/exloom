#!/usr/bin/env bash
# exloom — remove the worktree for task <n> after its branch has been integrated
# into the feature branch. By default it REFUSES unless the task branch is already
# merged (an ancestor of the feature branch), so you cannot silently discard
# unreviewed, un-integrated work. Pass --force to remove and discard anyway.
# Leaves the branch in place. Run from the feature-branch checkout.
#
# Usage: cleanup-task-worktree.sh <task-number> <feature-branch> [--force]

set -euo pipefail

N="${1:?usage: cleanup-task-worktree.sh <task-number> <feature-branch> [--force]}"
BASE="${2:?usage: cleanup-task-worktree.sh <task-number> <feature-branch> [--force]}"
FORCE=0
[ "${3:-}" = "--force" ] && FORCE=1

slug="${BASE#feature/}"; slug="${slug//\//-}"
BRANCH="task/${slug}/${N}"

if ! git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "no branch ${BRANCH}" >&2
  exit 1
fi

if [ "$FORCE" -ne 1 ]; then
  if ! git merge-base --is-ancestor "$BRANCH" "$BASE" 2>/dev/null; then
    echo "refusing: ${BRANCH} is not yet merged into ${BASE}. Integrate it first, or pass --force to discard it." >&2
    exit 1
  fi
fi

WT=""; path=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) path="${line#worktree }" ;;
    branch\ *) if [ "${line#branch }" = "refs/heads/${BRANCH}" ]; then WT="$path"; fi ;;
  esac
done < <(git worktree list --porcelain)

if [ -z "$WT" ]; then
  echo "no worktree found for ${BRANCH} (branch exists; maybe already removed)" >&2
  exit 1
fi

if [ "$FORCE" -eq 1 ]; then
  git worktree remove --force "$WT"
else
  git worktree remove "$WT"
fi
echo "removed ${WT}  (branch ${BRANCH} kept — delete with: git branch -d ${BRANCH})"
