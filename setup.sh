#!/usr/bin/env zsh
set -uo pipefail
zmodload zsh/datetime

PROBE_TIMEOUT=3

augmented_path() {
  local -a wanted parts
  wanted=(/opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin "$HOME/.local/bin" "$HOME/.orbstack/bin" /usr/bin /bin /usr/sbin /sbin)
  parts=("${(s.:.)PATH}")
  local w
  for w in "${wanted[@]}"; do
    [[ " ${parts[*]} " == *" $w "* ]] || parts+=("$w")
  done
  print -r -- "${(j.:.)parts}"
}

run_with_timeout() {
  local secs="$1"; shift
  "$@" >/dev/null 2>&1 &
  local pid=$! start=$EPOCHREALTIME
  while kill -0 "$pid" 2>/dev/null; do
    if (( EPOCHREALTIME - start >= secs )); then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.05
  done
  wait "$pid"
}

probe() {
  local bin="$1"; shift
  if ! command -v "$bin" >/dev/null 2>&1; then
    print -r -- "absent"
    return
  fi
  if run_with_timeout "$PROBE_TIMEOUT" "$bin" "$@"; then
    print -r -- "working"
  else
    print -r -- "present"
  fi
}

report_line() {
  local label="$1" state="$2"
  case "$state" in
    absent) print -r -- "$label: not installed" ;;
    present) print -r -- "$label: installed but not responding" ;;
    working) print -r -- "$label: working" ;;
  esac
}

main() {
  if (( # > 0 )); then
    print -r -- "setup.sh takes no arguments; it reports and changes nothing." >&2
    print -r -- "--apply was removed: it wrote a config key nothing read." >&2
    return 2
  fi

  export PATH="$(augmented_path)"

  local docker_state podman_state kubectl_state
  docker_state="$(probe docker version)"
  podman_state="$(probe podman version)"
  kubectl_state="$(probe kubectl version --request-timeout="${PROBE_TIMEOUT}s")"

  report_line "Docker" "$docker_state"
  report_line "Podman" "$podman_state"
  report_line "kubectl" "$kubectl_state"

  local -a working=()
  [[ "$docker_state" == "working" ]] && working+=("docker")
  [[ "$podman_state" == "working" ]] && working+=("podman")
  [[ "$kubectl_state" == "working" ]] && working+=("kubectl")

  print -r --
  if (( ${#working[@]} == 0 )); then
    print -r -- "no container runtime is answering here"
  else
    print -r -- "answering: ${(j:, :)working}"
  fi

  print -r --
  print -r -- "this is a read-only report and changes nothing."
  print -r -- "the bundled mac and apps providers do not use these runtimes;"
  print -r -- "this tells you what a container provider you write would find."
  print -r -- "to turn providers on or off, edit \${MAESTER_CONFIG_DIR:-~/.config/maester}/config.json — see README.md."

  return 0
}

main "$@"
