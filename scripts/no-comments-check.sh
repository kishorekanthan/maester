#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

violations=0

check_heredoc_line() {
  local file="$1" lineno="$2" line="$3" first="$4"
  if [ "$first" = true ] && [[ "$line" == '#!'* ]]; then
    return
  fi
  if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" == *'<!--'* ]]; then
    echo "$file:$lineno: comment line (heredoc body)"
    violations=$((violations + 1))
  fi
}

check_shell() {
  local file="$1"
  local in_heredoc=false
  local delim=""
  local strip_tabs=false
  local body_started=false
  local lineno=0
  local line probe
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ "$in_heredoc" = true ]; then
      probe="$line"
      if [ "$strip_tabs" = true ]; then
        probe="${probe#"${probe%%[!$'\t']*}"}"
      fi
      if [ "$probe" = "$delim" ]; then
        in_heredoc=false
        continue
      fi
      check_heredoc_line "$file" "$lineno" "$probe" "$body_started"
      body_started=false
      continue
    fi
    if [ "$lineno" -eq 1 ] && [[ "$line" == '#!'* ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      echo "$file:$lineno: comment line"
      violations=$((violations + 1))
    fi
    if [[ "$line" =~ \<\<(-?)[[:space:]]*\'([A-Za-z_][A-Za-z0-9_]*)\' ]]; then
      delim="${BASH_REMATCH[2]}"
      in_heredoc=true
      body_started=true
      [ "${BASH_REMATCH[1]}" = "-" ] && strip_tabs=true || strip_tabs=false
    elif [[ "$line" =~ \<\<(-?)[[:space:]]*\"([A-Za-z_][A-Za-z0-9_]*)\" ]]; then
      delim="${BASH_REMATCH[2]}"
      in_heredoc=true
      body_started=true
      [ "${BASH_REMATCH[1]}" = "-" ] && strip_tabs=true || strip_tabs=false
    elif [[ "$line" =~ [^\<]\<\<(-?)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*$ ]]; then
      delim="${BASH_REMATCH[2]}"
      in_heredoc=true
      body_started=true
      [ "${BASH_REMATCH[1]}" = "-" ] && strip_tabs=true || strip_tabs=false
    fi
  done < "$file"
}

check_swift() {
  local file="$1"
  local lineno=0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^[[:space:]]*// ]]; then
      echo "$file:$lineno: comment line"
      violations=$((violations + 1))
    fi
  done < "$file"
}

shell_files=()
while IFS= read -r -d '' f; do
  shell_files+=("$f")
done < <(find . -name "*.sh" -not -path "./.git/*" -not -path "./build/*" -print0)
for extra in build.sh install.sh setup.sh maester-doctor providers/apps providers/mac; do
  shell_files+=("./$extra")
done

seen=""
for f in "${shell_files[@]}"; do
  [ -f "$f" ] || continue
  key="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  case "$seen" in
    *"|$key|"*) continue ;;
  esac
  seen="$seen|$key|"
  check_shell "$f"
done

for f in Sources/*.swift; do
  check_swift "$f"
done

if [ "$violations" -gt 0 ]; then
  echo "no-comments check: $violations comment line(s) found" >&2
  exit 1
fi
echo "no-comments check: clean"
