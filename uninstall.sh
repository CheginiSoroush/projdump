#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump uninstaller — remove the command and the completion files
# ════════════════════════════════════════════════════════════════════════════
#  Homepage    https://github.com/CheginiSoroush/projdump
#
#  Usage:
#      ./uninstall.sh                  remove from the default prefix
#      ./uninstall.sh --prefix DIR     remove from DIR (as installed)
#      ./uninstall.sh --prefix=DIR     same, `=` form
#      ./uninstall.sh --help           show this help
#
#  Thin wrapper: execs `install.sh --uninstall` with the chosen prefix. If
#  install.sh is missing (partially deleted repo), a minimal inline fallback
#  removes the well-known files.
#  Exit codes:  0 success · 1 failure (unknown option, missing value)
#  SPDX-License-Identifier: MIT
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HOME}/.local"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      # FIX (1.1.0): a missing value used to hit `shift 2` and abort under
      # `set -e` with a cryptic error; fail with a clear message instead.
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "uninstall.sh: --prefix needs a directory" >&2
        exit 1
      fi
      PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    -h|--help)
      # Print the header comment block above (lines 2..18) as the help text.
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; break ;;
    *) echo "uninstall.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -x "$SCRIPT_DIR/install.sh" ]]; then
  exec "$SCRIPT_DIR/install.sh" --prefix "$PREFIX" --uninstall
fi

# Fallback: do it inline.
rm -f "$PREFIX/bin/projdump"
rm -f "$PREFIX/share/bash-completion/completions/projdump"
rm -f "$PREFIX/share/zsh/site-functions/_projdump"
echo "✅ projdump uninstalled"
