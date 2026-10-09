#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump installer — put projdump on your PATH and install completions
# ════════════════════════════════════════════════════════════════════════════
#  Homepage    https://github.com/CheginiSoroush/projdump
#
#  Usage:
#      ./install.sh                    install into ~/.local/bin (default)
#      ./install.sh --prefix DIR       install under DIR (e.g. /usr/local)
#      ./install.sh --prefix=DIR       same, `=` form
#      ./install.sh --uninstall        remove the symlink + completions
#      ./install.sh --help             show this help
#
#  What it does:
#    * verifies projdump.sh and lib/*.sh (bash -n) before touching anything
#    * symlinks projdump.sh into $PREFIX/bin — a later `git pull` keeps the
#      installation current, nothing is copied except completion files
#    * appends the bin directory to PATH in ~/.bashrc / ~/.zshrc (only if
#      it is not already covered)
#    * installs bash + zsh completions into $PREFIX/share
#
#  `--uninstall` reverses all of the above.
#  Exit codes:  0 success · 1 failure (bad option, syntax error, …)
#  SPDX-License-Identifier: MIT
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HOME}/.local"
DO_UNINSTALL=0

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ -t 1 ]] || { GREEN=''; YELLOW=''; RED=''; CYAN=''; NC=''; }

say()  { printf '%b\n' "${GREEN}   ✓ $*${NC}"; }
info() { printf '%b\n' "${YELLOW}   ℹ $*${NC}"; }
fail() { printf '%b\n' "${RED}   ✗ $*${NC}" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)    [[ $# -ge 2 ]] || fail "--prefix needs a directory"; PREFIX="$2"; shift 2 ;;
    --prefix=*)  PREFIX="${1#*=}"; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    -h|--help)
      # Print the header comment block above (lines 2..25) as the help text.
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

BIN_DIR="$PREFIX/bin"
DATA_DIR="$PREFIX/share"
BASH_COMP_DIR="$DATA_DIR/bash-completion/completions"
ZSH_COMP_DIR="$DATA_DIR/zsh/site-functions"

# ─── Uninstall ───────────────────────────────────────────────────────────────
if [[ "$DO_UNINSTALL" == "1" ]]; then
  rm -f "$BIN_DIR/projdump"
  rm -f "$BASH_COMP_DIR/projdump"
  rm -f "$ZSH_COMP_DIR/_projdump"
  printf '%b\n' "${GREEN}✅ projdump uninstalled${NC}"
  info "The PATH line in your shell rc was left in place."
  exit 0
fi

printf '%b\n' "${CYAN}Installing projdump…${NC}"
echo

# ─── Verify ──────────────────────────────────────────────────────────────────
[[ -f "$SCRIPT_DIR/projdump.sh" ]] || fail "projdump.sh not found in $SCRIPT_DIR"
bash -n "$SCRIPT_DIR/projdump.sh" || fail "syntax error in projdump.sh"
for lib in "$SCRIPT_DIR"/lib/*.sh; do
  [[ -e "$lib" ]] || continue
  bash -n "$lib" || fail "syntax error in ${lib##*/}"
done

# ─── Install ─────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
chmod +x "$SCRIPT_DIR/projdump.sh"
ln -sf "$SCRIPT_DIR/projdump.sh" "$BIN_DIR/projdump"
say "Command:  $BIN_DIR/projdump → $SCRIPT_DIR/projdump.sh"

# ─── PATH ────────────────────────────────────────────────────────────────────
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    touched=0
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [[ -f "$rc" ]] || continue
      grep -qs "$BIN_DIR" "$rc" && continue
      {
        printf '\n# projdump: add %s to PATH\n' "$BIN_DIR"
        # shellcheck disable=SC2016  # literal $PATH is intended in the rc file
        printf 'export PATH="%s:$PATH"\n' "$BIN_DIR"
      } >>"$rc"
      say "PATH line added to $rc"
      touched=1
    done
    [[ "$touched" == "1" ]] || info "No .bashrc/.zshrc found — add $BIN_DIR to PATH yourself"
    ;;
esac

# ─── Completions ─────────────────────────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/completions/projdump" ]]; then
  mkdir -p "$BASH_COMP_DIR" "$ZSH_COMP_DIR"
  cp -f "$SCRIPT_DIR/completions/projdump" "$BASH_COMP_DIR/projdump"
  cp -f "$SCRIPT_DIR/completions/projdump" "$ZSH_COMP_DIR/_projdump"
  say "Bash + zsh completions installed"
fi

echo
info "Activate now:   exec \$SHELL   (or: source ~/.bashrc)"
info "Usage:          projdump --help"

