#!/bin/sh

row() {
  printf '{"id":"%s","label":"%s","state":"ok","actions":[{"id":"open","label":"Open"}]}' "$1" "$2"
}

report() {
  printf '{"schema":1,"title":"Focus fixture","state":"ok","capabilities":{"stream":false,"refresh":600},"items":[%s,%s,%s]}\n' \
    "$(row alpha Alpha)" "$(row beta Beta)" "$(row gamma Gamma)"
}

case "${1:-}" in
  status) report ;;
  do) printf '%s %s\n' "${2:-}" "${3:-}" >> "$(dirname "$0")/../do.log" ;;
  *) exit 2 ;;
esac
