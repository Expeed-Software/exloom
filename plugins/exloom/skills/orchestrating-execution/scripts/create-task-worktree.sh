#!/usr/bin/env bash
# exloom — create an isolated worktree + branch for one parallel task, so an
# implementer can build task <n> without colliding with its siblings. Run from
# the feature-branch checkout (the controller's context). Prints the worktree
# path on success; hand that path to the implementer.
#
# Guards before creating: you are not on a protected branch, the base feature
# branch exists and is itself not protected, the working tree is clean (so the
# task worktree starts from a known committed base, not stale uncommitted or
# untracked work),
# and — as a warning, not a block — the gate marker is present.
#
# Branch name is task/<feature-slug>/<n>, so task 1 of one feature never collides
# with task 1 of another.
#
# Usage: create-task-worktree.sh <task-number> <feature-branch>

set -euo pipefail

N="${1:?usage: create-task-worktree.sh <task-number> <feature-branch>}"
BASE="${2:?usage: create-task-worktree.sh <task-number> <feature-branch>}"
[[ "$N" =~ ^[0-9]+$ ]] || { echo "task number must be a positive integer: $N" >&2; exit 1; }

is_protected() { case "$1" in main|master|dev|develop|HEAD) return 0 ;; *) return 1 ;; esac; }

CUR="$(git rev-parse --abbrev-ref HEAD)"
if is_protected "$CUR"; then
  echo "refusing: you are on protected branch '${CUR}'. Isolate onto a feature branch first (exloom:isolating-execution)." >&2
  exit 1
fi
if ! git show-ref --verify --quiet "refs/heads/${BASE}"; then
  echo "refusing: base branch '${BASE}' does not exist." >&2
  exit 1
fi
if is_protected "$BASE"; then
  echo "refusing: base '${BASE}' is protected — cut task branches from a feature branch, not from main/dev." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "refusing: working tree is not clean (uncommitted, staged, or untracked changes). Commit, stash, or gitignore them so the task worktree starts from a known base." >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
REPO="$(basename "$ROOT")"

if [ ! -f "${ROOT}/.claude/exloom-gate.enabled" ]; then
  echo "warning: .claude/exloom-gate.enabled not found — task branches will be isolated but NOT gated." >&2
fi

slug="${BASE#feature/}"; slug="${slug//\//-}"
BRANCH="task/${slug}/${N}"
WT="${ROOT%/*}/${REPO}-task-${slug}-${N}"

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "branch ${BRANCH} already exists — integrate or clean it up before reusing task ${N}." >&2
  exit 1
fi
if [ -e "$WT" ]; then
  echo "path ${WT} already exists — remove it first." >&2
  exit 1
fi

git worktree add -q "$WT" -b "$BRANCH" "$BASE"
echo "$WT"
