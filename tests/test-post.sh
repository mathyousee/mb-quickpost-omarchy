#!/bin/bash
set -euo pipefail
script=$(cd -- "$(dirname -- "$0")/.." && pwd)/microblog-post
fixture=$(mktemp -d)
trap 'rm -f "$fixture/.config/microblog/token" "$fixture/called" "$fixture/notice"; rmdir "$fixture/.config/microblog" "$fixture/.config" "$fixture"' EXIT
mkdir -p "$fixture/.config/microblog"
printf '# Test fixture\nfixture-token\n' > "$fixture/.config/microblog/token"
export HOME="$fixture" TEST_CONTENT=$'First line & 100% + café\nSecond line <not markup>'
export TEST_MODE=success

notify-send() { printf '%s\n' "$@" > "$HOME/notice"; }
curl() {
  local auth arg header='' body='' content=''
  IFS= read -r auth
  [[ $auth == "Authorization: Bearer fixture-token" ]] || return 90
  while (( $# )); do
    arg=$1
    shift
    case "$arg" in
      --dump-header) header=$1; shift;;
      --output) body=$1; shift;;
      --data-urlencode)
        case "$1" in
          h=entry) ;;
          content@/dev/fd/3) content=$(cat /dev/fd/3 && printf .); content=${content%.};;
          *) return 91;;
        esac
        shift;;
      *) [[ $arg != *"$TEST_CONTENT"* ]] || return 92;;
    esac
  done
  [[ $content == "$TEST_CONTENT" ]] || return 93
  printf called > "$HOME/called"
  : > "$header"
  : > "$body"
  case "$TEST_MODE" in
    success) printf 'Location: https://example.test/post/1\r\n' > "$header"; printf 201;;
    json) printf '{"url":"https://example.test/post/2"}' > "$body"; printf 201;;
    error) printf 'Unauthorized' > "$body"; printf 401; return 22;;
    timeout) printf 'Timed out' >&2; printf 000; return 28;;
    *) return 94;;
  esac
}
export -f notify-send curl

check() {
  local mode=$1 expected_status=$2 expected_notice=$3 status=0
  shift 3
  export TEST_MODE="$mode"
  rm -f "$HOME/called" "$HOME/notice"
  printf '%s' "$TEST_CONTENT" | bash "$script" "$@" || status=$?
  [[ $status == "$expected_status" ]]
  if [[ $expected_notice == silent ]]; then
    [[ ! -e $HOME/called && ! -e $HOME/notice ]]
  else
    grep -Fq "$expected_notice" "$HOME/notice"
  fi
  printf 'PASS %s %s\n' "$mode" "${*:-no arguments}"
}

check success 0 https://example.test/post/1 --stdin
check success 1 'Open microblog-compose'
[[ ! -e $HOME/called ]]
check json 0 https://example.test/post/2 --stdin
TEST_CONTENT+=$'\n\n'
check success 0 https://example.test/post/1 --stdin
check error 1 Unauthorized --stdin
check timeout 1 'Timed out' --stdin
TEST_CONTENT=''
check success 0 silent --stdin
TEST_CONTENT=$' \t\n'
check success 0 silent --stdin
printf '# Placeholder only\n' > "$HOME/.config/microblog/token"
TEST_CONTENT=hello
check success 1 'Paste one app token' --stdin
[[ ! -e $HOME/called ]]
