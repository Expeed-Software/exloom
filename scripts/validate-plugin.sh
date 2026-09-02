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

if [ "${1:-}" = "--commit-msg" ]; then
  # Message-only mode: nothing structural to validate, just the text.
  PLUGINS=""
elif [ -n "${1:-}" ]; then
  PLUGINS="$1"
else
  PLUGINS=$(python -c "
import json
m = json.load(open('$MARKETPLACE'))
print(' '.join(p['name'] for p in m.get('plugins', [])))
" 2>/dev/null)
fi

if [ -z "$PLUGINS" ] && [ "${1:-}" != "--commit-msg" ]; then
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
      # Authoring budgets. A skill is loaded into context every session, so
      # verbosity costs something on every run — enforced here rather than left
      # as advice, because a budget nothing checks is a preference.
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

      ;;
  esac

  # --- relative markdown links must resolve, in every plugin -------------------
  # A skill pointing at a missing reference fails silently at runtime, which is
  # the worst way to fail: the session simply does not get the content and has no
  # way to know it was meant to. Matches both `../refs/x.md` and a sibling
  # `x.md`, which is the form a split skill uses.
  broken=0
  while IFS= read -r md; do
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "$rel" in http*|'#'*) continue ;; esac
      if [ ! -f "$(dirname "$md")/$rel" ]; then
        fail "broken link in ${md#"$PLUGIN_ROOT/"} -> $rel"
        broken=$((broken + 1))
      fi
    done < <(grep -oE '\]\((\.\./)*[A-Za-z0-9/._-]+\.md\)' "$md" 2>/dev/null \
             | sed -e 's/^](//' -e 's/)$//' || true)
  done < <(find "$PLUGIN_ROOT" -name '*.md')
  if [ "$broken" -eq 0 ]; then
    echo "OK: all relative markdown links resolve"
  fi
done

# --- private context must not reach a public repo -----------------------------
#
# This is a hard gate, not a guideline, because the guideline failed repeatedly.
# Shipped files state the RULE and the MECHANISM. They do not carry where the
# rule came from: no branch names or ticket numbers, no round counts from a
# particular branch, no "on a real branch", no repository names, no session ids.
#
# A reader of this repo needs to know what the tool does and why the rule is
# right. They do not need, and must not be given, the internals of somebody's
# private codebase. Justify a rule with reasoning; never with an incident.
#
# Scans every shipped file plus the commit message being written, if one is
# passed as $2 with $1 = --commit-msg.

scan_private_context() {   # scan_private_context <label> <file>...
  local label="$1"; shift
  local hits
  hits="$(python - "$@" <<'PY'
import re, sys

# Narrative — checked everywhere. There is no legitimate reason for a shipped
# file or a commit message to cite a particular branch as its evidence.
NARRATIVE = [
    (r'\bon (a|one) real branch\b',             'cites a specific branch as evidence'),
    (r'\b(a|one) real branch\b',                'cites a specific branch as evidence'),
    (r'\bfrom a real branch\b',                 'cites a specific branch as evidence'),
    (r'\b(seen|observed|found) in the field\b', 'private incident narrative'),
    (r'\bone branch (ran|had|reached|spent)\b', 'private incident narrative'),
    (r'\ba branch (reached|spent|ran)\b',       'private incident narrative'),
    (r'\bin the wild\b',                        'private incident narrative'),
    (r'\bapptor',                               'private repository or product name'),
    # A UUID, unless it is all zeroes — that is the documented placeholder and
    # carries nothing. Anything else in this shape came from a real session.
    (r'\b(?!0{8}-0{4}-0{4}-0{4}-0{12})[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', 'session id'),
]

# Identifiers — checked only where a leak would actually ship: plugin files and
# commit messages. Test fixtures legitimately invent ids for a synthetic org, and
# flagging those would make this check noisy, and a noisy check gets switched off.
IDENTIFIERS = [
    (r'(?<![A-Za-z0-9.])2[0-9]{4}(?![A-Za-z0-9.])', 'looks like a real ticket number'),
    (r'\b(bug|feat|feature|task)/[0-9]{3,}',        'names a private branch'),
]

bad = []
for path in sys.argv[1:]:
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        continue
    norm = path.replace('\\', '/')
    rules = NARRATIVE + (IDENTIFIERS if not norm.startswith('scripts/') else [])
    for n, line in enumerate(text.splitlines(), 1):
        for pat, why in rules:
            if re.search(pat, line, re.IGNORECASE):
                bad.append(f"{path}:{n}: {why}\n      {line.strip()[:140]}")
                break
print("\n".join(bad))
PY
)"
  if [ -n "$hits" ]; then
    fail "$label carries private context that must not ship in a public repo:"
    printf '%s\n' "$hits" | sed 's/^/    /'
  else
    echo "OK: $label carries no private context"
  fi
}

if [ "${1:-}" = "--commit-msg" ]; then
  scan_private_context "commit message" "$2"
else
  # Every shipped file in every validated plugin, plus this repo's own scripts
  # and git hooks. This file is excluded because it necessarily contains the
  # patterns it searches for.
  SHIPPED=$(find plugins scripts .githooks -type f \
              \( -name '*.md' -o -name '*.sh' -o -name '*.json' -o -name 'commit-msg' \) 2>/dev/null \
            | grep -v 'validate-plugin.sh' || true)
  # shellcheck disable=SC2086
  [ -n "$SHIPPED" ] && scan_private_context "shipped files" $SHIPPED
fi

# --- summary ------------------------------------------------------------------

echo ""
echo "== Validation complete =="
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found"
  exit 1
fi
echo "PASSED"
