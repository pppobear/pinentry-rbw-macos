#!/bin/zsh
set -eu

log_file="/tmp/pinentry-rbw-wrapper.log"
{
  print -- "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  print -- "argv: $0 $*"
  print -- "cwd: $(pwd)"
  printenv | sort | sed -n '1,80p'
  print -- "---"
} >> "$log_file"

export PINENTRY_RBW_LOG="/tmp/pinentry-rbw.log"
exec "/Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos" "$@"
