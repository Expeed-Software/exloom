#!/usr/bin/env bash
# validate-plugin.sh — structural validation of the exloom plugin
# Usage: bash scripts/validate-plugin.sh
# Exits 0 if valid, 1 if any issues found.

set -e

PLUGIN_ROOT="plugins/exloom"
ERRORS=0

echo "== Validating $PLUGIN_ROOT =="

# 1. plugin.json exists and is valid JSON
if [ ! -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
  echo "FAIL: plugin.json not found"
  ERRORS=$((ERRORS + 1))
else
  if ! python -c "import json; json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))" 2>/dev/null; then
    echo "FAIL: plugin.json is not valid JSON"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK: plugin.json is valid JSON"
  fi
fi

# 2. Every SKILL.md has valid frontmatter with name + description
for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  # Skip references (it's not a skill)
  if [ "$skill_name" = "references" ]; then
    continue
  fi
  skill_file="$skill_dir/SKILL.md"
  if [ ! -f "$skill_file" ]; then
    echo "FAIL: $skill_dir has no SKILL.md"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  # Parse frontmatter using grep (no pyyaml dependency)
  # Check file starts with ---
  if ! head -1 "$skill_file" | grep -q '^---'; then
    result="FAIL:no_frontmatter"
  else
    # Extract name from frontmatter
    fm_name=$(sed -n '/^---$/,/^---$/p' "$skill_file" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//')
    fm_desc=$(sed -n '/^---$/,/^---$/p' "$skill_file" | grep '^description:' | head -1)
    if [ -z "$fm_name" ]; then
      result="FAIL:no_name"
    elif [ -z "$fm_desc" ]; then
      result="FAIL:no_description"
    elif [ "$fm_name" != "$skill_name" ]; then
      result="FAIL:name_mismatch:$fm_name"
    else
      result="OK"
    fi
  fi
  if [[ "$result" == OK* ]]; then
    echo "OK: $skill_name"
  else
    echo "FAIL: $skill_name -> $result"
    ERRORS=$((ERRORS + 1))
  fi
done

# 3. All templates exist
TEMPLATES_DIR="$PLUGIN_ROOT/assets/claude-md-templates"
EXPECTED_TEMPLATES=(
  default.md spring.md micronaut.md nodejs.md strapi.md fastapi.md react.md angular.md
)
for tpl in "${EXPECTED_TEMPLATES[@]}"; do
  if [ ! -f "$TEMPLATES_DIR/$tpl" ]; then
    echo "FAIL: template $tpl missing"
    ERRORS=$((ERRORS + 1))
  fi
done

# Summary
echo "== Validation complete =="
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found"
  exit 1
fi
echo "PASSED"
