#!/usr/bin/env bash
# validate-plugin.sh — structural validation of the plugins in this repo
# Usage: bash scripts/validate-plugin.sh [plugin-name]
#   No argument validates every plugin listed in .claude-plugin/marketplace.json.
# Exits 0 if valid, 1 if any issues found.

set -e

ERRORS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

# --- marketplace.json ---------------------------------------------------------

MARKETPLACE=".claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE" ]; then
  fail "$MARKETPLACE not found"
elif ! python -c "import json; json.load(open('$MARKETPLACE'))" 2>/dev/null; then
  fail "$MARKETPLACE is not valid JSON"
else
  echo "OK: marketplace.json is valid JSON"
fi

# --- which plugins to validate ------------------------------------------------

if [ -n "${1:-}" ]; then
  PLUGINS="$1"
else
  PLUGINS=$(python -c "
import json
m = json.load(open('$MARKETPLACE'))
print(' '.join(p['name'] for p in m.get('plugins', [])))
" 2>/dev/null)
fi

if [ -z "$PLUGINS" ]; then
  fail "no plugins to validate"
fi

# --- per-plugin validation ----------------------------------------------------

for plugin in $PLUGINS; do
  PLUGIN_ROOT="plugins/$plugin"
  echo ""
  echo "== Validating $PLUGIN_ROOT =="

  if [ ! -d "$PLUGIN_ROOT" ]; then
    fail "$PLUGIN_ROOT directory not found"
    continue
  fi

  # 1. plugin.json exists, is valid JSON, and its name matches the directory
  MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  if [ ! -f "$MANIFEST" ]; then
    fail "plugin.json not found in $PLUGIN_ROOT"
  elif ! python -c "import json; json.load(open('$MANIFEST'))" 2>/dev/null; then
    fail "$MANIFEST is not valid JSON"
  else
    manifest_name=$(python -c "import json; print(json.load(open('$MANIFEST')).get('name',''))")
    if [ "$manifest_name" != "$plugin" ]; then
      fail "plugin.json name '$manifest_name' does not match directory '$plugin'"
    else
      echo "OK: plugin.json is valid JSON and name matches"
    fi
  fi

  # 2. Every SKILL.md has valid frontmatter with name + description matching its folder
  if [ -d "$PLUGIN_ROOT/skills" ]; then
    for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "$skill_dir")
      # references/ holds shared reference files, not a skill
      if [ "$skill_name" = "references" ]; then
        continue
      fi
      skill_file="$skill_dir/SKILL.md"
      if [ ! -f "$skill_file" ]; then
        fail "$skill_dir has no SKILL.md"
        continue
      fi
      if ! head -1 "$skill_file" | grep -q '^---'; then
        result="FAIL:no_frontmatter"
      else
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
        echo "OK: skill $skill_name"
      else
        fail "skill $skill_name -> $result"
      fi
    done
  fi

  # 3. Plugin-specific checks
  case "$plugin" in
    exloom)
      TEMPLATES_DIR="$PLUGIN_ROOT/assets/claude-md-templates"
      EXPECTED_TEMPLATES=(
        default.md spring.md micronaut.md nodejs.md strapi.md fastapi.md react.md angular.md
      )
      for tpl in "${EXPECTED_TEMPLATES[@]}"; do
        if [ ! -f "$TEMPLATES_DIR/$tpl" ]; then
          fail "template $tpl missing"
        fi
      done
      ;;

    exloom-qa)
      # Authoring budgets — plan section 4a. A skill is loaded into context every
      # session, so verbosity costs compliance on every run. Enforced, not advised.
      SKILL_MAX=150
      REF_MAX=200
      if [ -d "$PLUGIN_ROOT/skills" ]; then
        for skill_file in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
          [ -f "$skill_file" ] || continue
          lines=$(wc -l < "$skill_file")
          if [ "$lines" -gt "$SKILL_MAX" ]; then
            fail "$(basename "$(dirname "$skill_file")")/SKILL.md is $lines lines (budget $SKILL_MAX) — move content to a reference file"
          fi
        done
        for ref_file in "$PLUGIN_ROOT"/skills/references/*.md; do
          [ -f "$ref_file" ] || continue
          lines=$(wc -l < "$ref_file")
          if [ "$lines" -gt "$REF_MAX" ]; then
            fail "references/$(basename "$ref_file") is $lines lines (budget $REF_MAX)"
          fi
        done
      fi

      # Relative markdown links must resolve — a skill pointing at a missing
      # reference fails silently at runtime, which is the worst way to fail.
      broken=0
      while IFS= read -r md; do
        while IFS= read -r rel; do
          [ -n "$rel" ] || continue
          if [ ! -f "$(dirname "$md")/$rel" ]; then
            fail "broken link in ${md#"$PLUGIN_ROOT/"} -> $rel"
            broken=$((broken + 1))
          fi
        done < <(grep -o '\.\./[A-Za-z0-9/._-]*\.md' "$md" || true)
      done < <(find "$PLUGIN_ROOT" -name '*.md')
      if [ "$broken" -eq 0 ]; then
        echo "OK: all relative markdown links resolve"
      fi
      ;;
  esac
done

# --- summary ------------------------------------------------------------------

echo ""
echo "== Validation complete =="
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found"
  exit 1
fi
echo "PASSED"
