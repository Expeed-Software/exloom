#!/usr/bin/env bash
# exloom — copy one task's section out of a plan file into its own file, and
# print that file's path. Hand the path (not the text) to an implementer subagent
# so the brief never bloats the controller's context.
#
# A task is a markdown heading whose text starts with "Task <n>"; its section runs
# until the next heading at the same or shallower level (sub-headings inside the
# task are kept). Headings inside fenced ``` code blocks are ignored.
#
# Usage: task-brief.sh <plan-file> <task-number>

set -euo pipefail

plan=${1:?usage: task-brief.sh <plan-file> <task-number>}
num=${2:?usage: task-brief.sh <plan-file> <task-number>}
[[ $num =~ ^[0-9]+$ ]] || { printf 'task number must be a positive integer: %s\n' "$num" >&2; exit 1; }
[[ -f $plan ]] || { printf 'plan not found: %s\n' "$plan" >&2; exit 1; }

root=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
dest_dir=$root/.exloom/execution
mkdir -p "$dest_dir"
dest=$dest_dir/task-$num-brief.md

: > "$dest"
in_section=0
in_fence=0
found=0
task_level=0

while IFS= read -r line || [[ -n $line ]]; do
  # toggle on fence delimiters so `#` comments in code aren't mistaken for headings
  [[ $line == '```'* ]] && in_fence=$(( 1 - in_fence ))

  heading_level=0
  if [[ $in_fence -eq 0 && $line =~ ^(#{1,6})[[:space:]] ]]; then
    heading_level=${#BASH_REMATCH[1]}
  fi

  if [[ $in_section -eq 0 ]]; then
    if [[ $heading_level -gt 0 && $line =~ ^#{1,6}[[:space:]]+Task[[:space:]]+${num}([^0-9]|$) ]]; then
      in_section=1
      found=1
      task_level=$heading_level
      printf '%s\n' "$line" >> "$dest"
    fi
    continue
  fi

  # a heading at the same or shallower level ends the task; deeper sub-headings
  # inside the task are kept
  [[ $heading_level -gt 0 && $heading_level -le $task_level ]] && break
  printf '%s\n' "$line" >> "$dest"
done < "$plan"

if [[ $found -eq 0 ]]; then
  printf 'Task %s not found in %s\n' "$num" "$plan" >&2
  rm -f "$dest"
  exit 1
fi
printf '%s\n' "$dest"
