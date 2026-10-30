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
    pv=$(python -c "import json; print(json.load(open('$MANIFEST')).get('version',''))")
    mv=$(python -c "import json; print(next((p.get('version','') for p in json.load(open('$MARKETPLACE'))['plugins'] if p['name']=='$plugin'),''))")
    if [ "$pv" != "$mv" ]; then
      fail "$plugin: plugin.json version '$pv' differs from marketplace.json '$mv'"
    else
      echo "OK: plugin.json and marketplace.json both say $pv"
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

  # 2b. Commands and agents need frontmatter with a name and a description too.
  for f in "$PLUGIN_ROOT"/commands/*.md "$PLUGIN_ROOT"/agents/*.md; do
    [ -f "$f" ] || continue
    if ! head -1 "$f" | grep -q '^---' \
       || ! sed -n '/^---$/,/^---$/p' "$f" | grep -q '^name:' \
       || ! sed -n '/^---$/,/^---$/p' "$f" | grep -q '^description:'; then
      fail "${f#"$PLUGIN_ROOT/"} has no frontmatter with name and description"
    fi
  done

  # 2c. Claude Code drops a component whose frontmatter is not valid YAML, without an error.
  yaml_errors=$(python - "$PLUGIN_ROOT" <<'YAMLPY'
import glob, os, sys
try:
    import yaml
except ImportError:
    print("PyYAML is not installed (pip install pyyaml); frontmatter cannot be checked")
    sys.exit()
root = sys.argv[1]
files = glob.glob(os.path.join(root, "skills", "*", "SKILL.md")) + glob.glob(os.path.join(root, "commands", "*.md")) + glob.glob(os.path.join(root, "agents", "*.md"))
for f in sorted(files):
    lines = open(f, encoding="utf-8").read().splitlines()
    rel = os.path.relpath(f, root).replace(os.sep, "/")
    if not lines or lines[0].strip() != "---" or "---" not in [l.strip() for l in lines[1:]]:
        continue
    end = [l.strip() for l in lines[1:]].index("---") + 1
    try:
        data = yaml.safe_load("\n".join(lines[1:end]))
        if not isinstance(data, dict):
            print(f"{rel}: frontmatter is not a YAML mapping")
    except yaml.YAMLError as e:
        print(f"{rel}: invalid YAML frontmatter: {str(e).splitlines()[0]}")
YAMLPY
)
  if [ -n "$yaml_errors" ]; then
    while IFS= read -r line; do fail "$line"; done <<< "$yaml_errors"
  fi

  # 3. Plugin-specific checks
  case "$plugin" in
    exloom)
      TEMPLATES_DIR="$PLUGIN_ROOT/assets/claude-md-templates"
      EXPECTED_TEMPLATES=(
        default.md spring.md micronaut.md nodejs.md strapi.md fastapi.md react.md angular.md dotnet.md flutter.md
      )
      for tpl in "${EXPECTED_TEMPLATES[@]}"; do
        if [ ! -f "$TEMPLATES_DIR/$tpl" ]; then
          fail "template $tpl missing"
        fi
      done
      [ -f "$PLUGIN_ROOT/skills/brainstorming/ui-mock.md" ] || fail "brainstorming/ui-mock.md missing"
      DOCS_SKILL="$PLUGIN_ROOT/skills/maintaining-reference-docs/SKILL.md"
      if [ -f "$DOCS_SKILL" ]; then
        words=$(wc -w < "$DOCS_SKILL")
        if [ "$words" -lt 800 ] || [ "$words" -gt 1500 ]; then
          fail "maintaining-reference-docs/SKILL.md is $words words (800-1500)"
        fi
      else
        fail "skill maintaining-reference-docs missing"
      fi
      # v5 wording and direct-run instructions: /exloom is the only entry point.
      V5_RE='declared tier|Propose a tier|Merge as-is'
      DIRECT_RE='(^|[^A-Za-z/`])([Rr]un|[Rr]e-run|[Ii]nvoke|[Uu]se|[Ff]ollow|[Ss]uggest|[Nn]ext( command)?s?:)[^.|]{0,40}/(review-init|smoke-test|review-complete)'
      while IFS= read -r f; do
        case "$f" in */commands/exloom.md) re="$V5_RE" ;; *) re="$V5_RE|$DIRECT_RE" ;; esac
        hits=$(grep -nE "$re" "$f" || true)
        if [ -n "$hits" ]; then
          fail "v5 wording in ${f#"$PLUGIN_ROOT/"}:"
          echo "$hits" | sed 's/^/    /'
        fi
      done < <(find "$PLUGIN_ROOT" \( -name '*.md' -o -name '*.sh' \) -type f)
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

# --- unpinned launchers -------------------------------------------------------
# npx and uvx fetch and run whatever the registry serves, which is a package the
# project never installed; @latest pins nothing. The directory portal rejects
# them, and they have been removed from this plugin twice.

for plugin in $PLUGINS; do
  PLUGIN_ROOT="plugins/$plugin"
  [ -d "$PLUGIN_ROOT" ] || continue
  launchers=$(grep -rlE '(^|[^A-Za-z-])(npx|uvx)[[:space:]]|@latest' "$PLUGIN_ROOT"       --include='*.sh' --include='*.md' --include='*.json' 2>/dev/null       | grep -v '/templates/' || true)
  if [ -n "$launchers" ]; then
    fail "unpinned launcher (npx/uvx/@latest) in $plugin:"
    echo "$launchers" | sed 's|^|    |'
    echo "    Use the project's own binary, e.g. ./node_modules/.bin/<tool>."
  else
    echo "OK: $plugin ships no unpinned launcher"
  fi
done

# --- the docs describe what ships ---------------------------------------------
# The inventory was wrong for a whole release — still "10 skills" after an
# eleventh shipped. Counting is cheap; noticing afterwards is not.

for plugin in $PLUGINS; do
  PLUGIN_ROOT="plugins/$plugin"
  RDM="$PLUGIN_ROOT/README.md"
  [ -f "$RDM" ] || continue
  for kind in skills agents commands scripts templates; do
    claimed=$(grep -oE "[*][*][0-9]+ $kind[*][*]" "$RDM" 2>/dev/null | head -1 | grep -oE "[0-9]+" || true)
    [ -n "$claimed" ] || continue
    case "$kind" in
      skills)    actual=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) ;;
      templates) actual=$(find "$PLUGIN_ROOT/templates" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l) ;;
      scripts)   actual=$(find "$PLUGIN_ROOT/scripts" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l) ;;
      *)         actual=$(find "$PLUGIN_ROOT/$kind" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l) ;;
    esac
    actual=$(echo "$actual" | tr -d ' ')
    if [ "$claimed" != "$actual" ]; then
      fail "$plugin README says $claimed $kind, $actual ship"
    else
      echo "OK: $plugin README names $actual $kind"
    fi
  done

  # Every step the router can return must be documented, or a developer who is
  # stopped on one has nothing to read.
  HIW="$PLUGIN_ROOT/HOW-IT-WORKS.md"
  LIB="$PLUGIN_ROOT/hooks/lib.sh"
  if [ -f "$HIW" ] && [ -f "$LIB" ]; then
    undocumented=""
    for st in $(sed -n '/^exloom_next_step() {/,/^}/p' "$LIB"                  | grep -oE 'echo [a-z-]+' | awk '{print $2}' | sort -u); do
      grep -q -- "$st" "$HIW" || undocumented="$undocumented $st" || true
    done
    if [ -n "$undocumented" ]; then
      fail "$plugin HOW-IT-WORKS.md documents no step:$undocumented"
    else
      echo "OK: $plugin documents every step it can stop on"
    fi
  fi
done

# --- summary ------------------------------------------------------------------

echo ""
echo "== Validation complete =="
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found"
  exit 1
fi
echo "PASSED"
