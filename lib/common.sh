#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump · lib/common.sh — shared helpers
# ════════════════════════════════════════════════════════════════════════════
#  Sourced by projdump.sh (also usable standalone). Provides:
#
#    ok msg…     success line   (green,  stdout)
#    inf msg…    info line      (yellow, stdout)
#    err msg…    error line     (red,    stderr)
#
#  The colour palette (C_GREEN C_YELLOW C_RED C_CYAN C_BOLD C_NC) is
#  exported as read-only variables for callers. Colours are enabled only
#  when stdout is a TTY and NO_COLOR is unset — see https://no-color.org.
#  SPDX-License-Identifier: MIT
# ════════════════════════════════════════════════════════════════════════════

# Only colourise when stdout is a TTY and NO_COLOR is not set.
# C_CYAN / C_BOLD are part of the palette for callers, not used by ok/inf/err.
# shellcheck disable=SC2034
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly C_GREEN='\033[0;32m'
  readonly C_YELLOW='\033[1;33m'
  readonly C_RED='\033[0;31m'
  readonly C_CYAN='\033[0;36m'
  readonly C_BOLD='\033[1m'
  readonly C_NC='\033[0m'
else
  readonly C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_BOLD='' C_NC=''
fi

ok()  { echo -e "${C_GREEN}$*${C_NC}"; }
inf() { echo -e "${C_YELLOW}$*${C_NC}"; }
err() { echo -e "${C_RED}$*${C_NC}" >&2; }

