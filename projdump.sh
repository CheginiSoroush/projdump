#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump — dump an entire codebase into a single LLM-ready file
# ════════════════════════════════════════════════════════════════════════════
#  Homepage    https://github.com/CheginiSoroush/projdump
#  Docs        https://cheginisoroush.github.io/projdump/
#  Version     2.0.1
#  License     MIT — see the LICENSE file in this repository
#
#  SYNOPSIS
#      projdump [output] [options]
#
#  DESCRIPTION
#      Collects every text file of a project (respecting .gitignore inside
#      git repositories) and writes it — together with a directory tree,
#      per-file metadata and a statistics summary — into ONE file that can
#      be pasted straight into an LLM chat (Claude, ChatGPT, DeepSeek,
#      Gemini, …).
#
#      Output formats:
#        md    Markdown with syntax-tagged fenced code blocks (default)
#        xml   Claude-friendly <file> blocks; content wrapped in CDATA
#        json  jq-friendly object; file content byte-identical to source
#
#  v2.0.0 — THE FAST ONE
#      v1 forked ~6 helper processes per file (~40s on a 2000-file repo).
#      v2 batches everything:
#        * ONE python3 process scans every file (size, lines, binary,
#          fences, CDATA markers — and JSON-encodes content when needed)
#        * without python3: one GNU stat(1) batch, then lazy probes
#        * pure-bash tree renderer (tree(1) is no longer needed) with
#          --tree-depth support
#        * pure-bash human_size + cached language tags — zero subshells
#          per file
#      Plus: .projdumprc config, --split parts, --model budgets,
#      --git-log, weighted token estimates and best-effort .gitignore
#      handling outside git repos.
#
#  DESIGN RULES
#    * Zero hard dependencies beyond bash 5.0+ and find/git.
#      Optional helpers (python3, jq) are used when present and gracefully
#      skipped when not. python3 unlocks the fast path.
#    * A dump can never contain or corrupt itself: the output path is
#      always excluded, Markdown fences grow past any run of backticks
#      in the source, CDATA sections are split on "]]>" and XML
#      attributes are escaped.
#    * File pipelines are NUL-delimited, so filenames containing spaces,
#      tabs or literal newlines survive all three output formats.
#    * Config files are executable shell code, so they are never sourced
#      from the project being dumped: only the user's own XDG config is
#      auto-loaded; a project-local .projdumprc must be passed explicitly
#      via --config (an opt-in trust decision, like `source`).
#    * Runs 100% locally — no network access, no telemetry, ever.
#
#  EXIT CODES
#      0  success
#      1  usage error, invalid option/ref, or write failure
#
#  ENVIRONMENT
#      NO_COLOR=1  disable colours (also auto-disabled when piped)
#
#  EXAMPLES
#      projdump                              # <project>_dump.md in the cwd
#      projdump --model claude-sonnet        # fit ~180k tokens
#      projdump --split 60k                  # multiple parts, each ≤60k
#      projdump --since HEAD~5 --git-log 10  # recent changes + history
#      projdump --format xml --note 'review auth'
#
#  SPDX-License-Identifier: MIT
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

readonly SCRIPT_VERSION="2.0.1"
readonly SCRIPT_NAME="projdump"

# bash 5.2 enables `patsub_replacement` by default: a bare `&` in the
# replacement of ${var//pat/repl} expands to the matched text, which corrupts
# xml_escape() ("&quot; became '"quot;'). Turn it off globally; on older bash
# versions the option does not exist and this is a harmless no-op.
shopt -u patsub_replacement 2>/dev/null || true

# ─── Output helpers (lib/common.sh, inlined in v2) ───────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  # shellcheck disable=SC2034  # C_CYAN/C_BOLD are exported for callers
  readonly C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_RED='\033[0;31m'
  readonly C_CYAN='\033[0;36m'  C_BOLD='\033[1m'      C_NC='\033[0m'
else
  # shellcheck disable=SC2034
  readonly C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_BOLD='' C_NC=''
fi
# Human-facing messages (status/notes) go to stderr so that --stdout stays
# machine-readable: `projdump --stdout --format json | jq` needs no --quiet.
ok()  { printf '%b\n' "${C_GREEN}$*${C_NC}" >&2; }
inf() { printf '%b\n' "${C_YELLOW}$*${C_NC}" >&2; }
err() { printf '%b\n' "${C_RED}$*${C_NC}" >&2; }
die() { err "$SCRIPT_NAME: $*"; exit 1; }

# ─── Optional tool availability (checked once) ───────────────────────────────
HAVE_PY3=0 HAVE_JQ=0 HAVE_GIT=0 HAVE_GNU_STAT=0
command -v python3 >/dev/null 2>&1 && HAVE_PY3=1
command -v jq       >/dev/null 2>&1 && HAVE_JQ=1
command -v git      >/dev/null 2>&1 && HAVE_GIT=1
if stat --version >/dev/null 2>&1; then HAVE_GNU_STAT=1; fi

# ─── Defaults ────────────────────────────────────────────────────────────────
OUT=""
SHOW_TREE=1
EXT_FILTER=""
MAX_FILE_SIZE=500      # KB; 0 = unlimited
FORMAT="md"            # md | xml | json
STDOUT=0
QUIET=0
VERBOSE=0
LIST_ONLY=0
SINCE=""
BUDGET=0               # 0 = unlimited (estimated tokens)
SORT_KEY="name"        # name | size | size-desc | ext
NOTE=""
EXCLUDES=()
INCLUDES=()
COPY_MODE="auto"       # auto | yes | no
TREE_DEPTH=0           # 0 = unlimited
GIT_LOG=0              # include last N commits
JOBS=0                 # 0 = auto
SPLIT_TOK=0            # 0 = no splitting
CONFIG_FILE=""

# ════════════════════════════════════════════════════════════════════════════
#  Usage
# ════════════════════════════════════════════════════════════════════════════
usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — dump an entire project into one AI-ready file

Usage:
  ${SCRIPT_NAME} [output] [options]

Output:
  -o, --output FILE      Output file (default: <project>_dump.<ext>)
  -f, --format md|xml|json
                         Output format (default: md)
      --split N[k|m]     Write multiple parts, each ≤ N tokens
                         (e.g. --split 60k → <name>_dump.part1.md …)

Selecting files:
  -e, --ext-only sh,md   Only include files with these extensions
  -x, --exclude GLOB     Skip paths matching GLOB (repeatable)
  -i, --include GLOB     Only include paths matching GLOB (repeatable)
      --since REF        Only files changed since a git ref (needs git)
      --max-size N       Skip files larger than N KB (default: ${MAX_FILE_SIZE}, 0 = off)

Ordering & budget:
      --sort KEY         name | size | size-desc | ext   (default: name)
      --tokens-budget N  Stop adding files once ~N tokens are reached
      --model NAME       Preset token budget for a model (see --list-models)
      --list-models      Show available model presets and exit

Extras:
      --no-tree          Don't include the directory tree
      --tree-depth N     Limit tree depth (default: unlimited)
      --note TEXT        Add a "note for the AI" block at the top
      --git-log N        Include the last N commits in the dump
  -j, --jobs N           Parallel workers for fallback probing (default: auto)
      --config FILE      Use this config file (default:
                         \$XDG_CONFIG_HOME/projdump/config; project-local
                         files are never sourced unless given here)
      --no-config        Ignore all config files

Info:
      --list, --dry-run  Dry run: print what would be dumped and exit
      --stdout           Write the dump to stdout instead of a file
                         (status messages go to stderr)
      --copy | --no-copy Force / disable clipboard copy (default: auto)
  -v, --verbose          Explain skipped files on stderr
  -q, --quiet            Don't print the summary
      --version          Show version
  -h, --help             Show this help

Examples:
  ${SCRIPT_NAME}                              # <project>_dump.md in the cwd
  ${SCRIPT_NAME} --model claude-sonnet        # fit a 200k context
  ${SCRIPT_NAME} --split 60k                  # chunked for long chats
  ${SCRIPT_NAME} --since HEAD~5 --git-log 10  # recent changes + history
  ${SCRIPT_NAME} -e sh,bats -x 'test/*'      # only shell files
  ${SCRIPT_NAME} --format xml --note 'Review auth for security bugs'
EOF
}

list_models() {
  cat <<'EOF'
Model presets (--model NAME → --tokens-budget set to ~90% of context):

  NAME            CONTEXT      BUDGET
  gpt-4o          128k         115200
  gpt-4.1         1M           900000
  o3              200k         180000
  claude-sonnet   200k         180000
  claude-opus     200k         180000
  gemini-2.5-pro  1M           900000
  deepseek-v3     128k         115200
  llama-3.1       128k         115200
EOF
}

model_budget() {
  case "$1" in
    gpt-4o)              echo 115200 ;;
    gpt-4.1)             echo 900000 ;;
    o3)                  echo 180000 ;;
    claude-sonnet|claude) echo 180000 ;;
    claude-opus)         echo 180000 ;;
    gemini-2.5-pro|gemini) echo 900000 ;;
    deepseek-v3|deepseek) echo 115200 ;;
    llama-3.1|llama)     echo 115200 ;;
    *) return 1 ;;
  esac
}

require_value() {
  [[ $# -ge 2 && -n "${2:-}" ]] || die "option '$1' requires a value"
}

# ════════════════════════════════════════════════════════════════════════════
#  Config file — sourced BEFORE flag parsing so flags win.
#  Recognised keys: FORMAT, MAX_FILE_SIZE, EXT_FILTER, SHOW_TREE, TREE_DEPTH,
#  SORT_KEY, BUDGET (alias TOKENS_BUDGET), NOTE, EXCLUDES=(…), INCLUDES=(…),
#  COPY_MODE, GIT_LOG, JOBS, SPLIT, MODEL.
#
#  SECURITY (v2.0.1): a config file is executable shell code, so it is never
#  loaded from the project being dumped. Only the user's own XDG config is
#  auto-loaded; a project-local .projdumprc must be passed explicitly with
#  --config .projdumprc (the same trust decision as `source`).
# ════════════════════════════════════════════════════════════════════════════
load_config() {
  local cfg="$1"
  [[ -f "$cfg" ]] || die "config file not found: '$cfg'"
  # shellcheck source=/dev/null
  source "$cfg"
  CONFIG_LOADED_FROM="$cfg"
}

find_config() {
  # Auto-load ONLY the user's own XDG config — never files from the project.
  local c="${XDG_CONFIG_HOME:-$HOME/.config}/projdump/config"
  if [[ -f "$c" ]]; then
    printf '%s' "$c"
    return 0
  fi
  return 1
}

CONFIG_LOADED_FROM=""
{
  # Pre-scan a COPY of the args for --config/--no-config so the config is in
  # place before the main parse appends flags on top of it.
  args_copy=("$@")
  pre_noconfig=0
  for ((ai = 0; ai < ${#args_copy[@]}; ai++)); do
    case "${args_copy[$ai]}" in
      --config)     CONFIG_FILE="${args_copy[$((ai+1))]:-}" ;;
      --no-config)  pre_noconfig=1 ;;
    esac
  done
  if (( ! pre_noconfig )); then
    if [[ -n "$CONFIG_FILE" ]]; then
      load_config "$CONFIG_FILE"
    elif cfg_auto="$(find_config)"; then
      load_config "$cfg_auto"
    elif [[ -f "./.projdumprc" ]]; then
      # Migration notice (v2.0.1): the project-local rc used to be sourced
      # automatically — point old users at the explicit, safe form.
      inf "note: found ./.projdumprc — project configs are no longer auto-loaded; use --config .projdumprc (pass --no-config to silence)"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════════════
#  Parse args (flags override the config file)
# ════════════════════════════════════════════════════════════════════════════
MODEL_GIVEN=""
SPLIT_RAW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tree)   SHOW_TREE=0; shift ;;
    --tree-depth) require_value "$@"; TREE_DEPTH="$2"; shift 2 ;;
    --git-log)   require_value "$@"; GIT_LOG="$2"; shift 2 ;;
    --ext-only|-e)     require_value "$@"; EXT_FILTER="$2"; shift 2 ;;
    --exclude|-x)      require_value "$@"; EXCLUDES+=("$2"); shift 2 ;;
    --include|-i)      require_value "$@"; INCLUDES+=("$2"); shift 2 ;;
    --max-size)  require_value "$@"; MAX_FILE_SIZE="$2"; shift 2 ;;
    --format|-f) require_value "$@"; FORMAT="$2"; shift 2 ;;
    --output|-o) require_value "$@"; OUT="$2"; shift 2 ;;
    --since)     require_value "$@"; SINCE="$2"; shift 2 ;;
    --sort)      require_value "$@"; SORT_KEY="$2"; shift 2 ;;
    --tokens-budget) require_value "$@"; BUDGET="$2"; shift 2 ;;
    --model)     require_value "$@"; MODEL_GIVEN="$2"; shift 2 ;;
    --list-models) list_models; exit 0 ;;
    --split)     require_value "$@"; SPLIT_RAW="$2"; shift 2 ;;
    --jobs|-j)   require_value "$@"; JOBS="$2"; shift 2 ;;
    --note)      require_value "$@"; NOTE="$2"; shift 2 ;;
    --config)    require_value "$@"; shift 2 ;;   # value validated; config was loaded by the pre-scan
    --no-config) shift ;;
    --list|--dry-run) LIST_ONLY=1; shift ;;
    --stdout|-)  STDOUT=1; shift ;;
    --copy)      COPY_MODE="yes"; shift ;;
    --no-copy)   COPY_MODE="no"; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -q|--quiet)  QUIET=1; shift ;;
    --version)   echo "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 ;;
    -h|--help)   usage; exit 0 ;;
    --)
      shift
      if [[ $# -gt 0 ]]; then OUT="$1"; shift; fi
      break
      ;;
    -*)          err "Unknown option: $1"; usage >&2; exit 1 ;;
    *)           OUT="$1"; shift ;;
  esac
done

# ─── Validation ──────────────────────────────────────────────────────────────
case "$FORMAT" in md|xml|json) ;; *) die "Unknown format: '$FORMAT' (use md, xml or json)" ;; esac
[[ "$MAX_FILE_SIZE" =~ ^[0-9]+$ ]] || die "--max-size expects a number, got '$MAX_FILE_SIZE'"
[[ "$BUDGET" =~ ^[0-9]+$ ]] || die "--tokens-budget expects a number, got '$BUDGET'"
[[ "$TREE_DEPTH" =~ ^[0-9]+$ ]] || die "--tree-depth expects a number, got '$TREE_DEPTH'"
[[ "$GIT_LOG" =~ ^[0-9]+$ ]] || die "--git-log expects a number, got '$GIT_LOG'"
[[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs expects a number, got '$JOBS'"
case "$SORT_KEY" in name|size|size-desc|ext) ;; *) die "Unknown sort key: '$SORT_KEY' (use name, size, size-desc or ext)" ;; esac

if [[ -n "$SPLIT_RAW" ]]; then
  case "$SPLIT_RAW" in
    *k|*K) SPLIT_TOK="$((${SPLIT_RAW%[kK]} * 1000))" ;;
    *m|*M) SPLIT_TOK="$((${SPLIT_RAW%[mM]} * 1000000))" ;;
    *)     SPLIT_TOK="$SPLIT_RAW" ;;
  esac
  [[ "$SPLIT_TOK" =~ ^[0-9]+$ ]] || die "--split expects N, Nk or Nm (tokens per part), got '$SPLIT_RAW'"
  (( SPLIT_TOK > 0 )) || die "--split must be > 0"
  (( LIST_ONLY )) && die "--split cannot be combined with --list"
  (( STDOUT )) && die "--split requires writing files (not --stdout)"
fi

if [[ -n "$MODEL_GIVEN" ]]; then
  if ! mb="$(model_budget "$MODEL_GIVEN")"; then
    err "Unknown model: '$MODEL_GIVEN'"
    list_models >&2
    exit 1
  fi
  if (( BUDGET == 0 )); then
    BUDGET="$mb"
    (( VERBOSE )) && inf "→ model preset: $MODEL_GIVEN → token budget $BUDGET"
  else
    inf "note: --tokens-budget given, ignoring --model '$MODEL_GIVEN'"
  fi
fi

if (( STDOUT )) && [[ -n "$OUT" ]]; then
  inf "note: --stdout given, ignoring the output path '$OUT'"
  OUT=""
fi
if (( LIST_ONLY )) && [[ -n "$OUT" ]]; then
  inf "note: --list given, ignoring the output path '$OUT'"
  OUT=""
fi

# --since validation (fail early and clearly)
if [[ -n "$SINCE" ]]; then
  if (( ! HAVE_GIT )); then
    die "--since requires git"
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "--since must run inside a git repository"
  fi
  if ! git rev-parse --verify --quiet "${SINCE}^{commit}" >/dev/null 2>&1; then
    die "invalid git ref: '$SINCE'"
  fi
fi

PROJECT_NAME="$(basename "$PWD")"

# Auto output name
if [[ -z "$OUT" && "$STDOUT" -eq 0 && "$LIST_ONLY" -eq 0 ]]; then
  case "$FORMAT" in
    md)   OUT="${PROJECT_NAME}_dump.md" ;;
    xml)  OUT="${PROJECT_NAME}_dump.xml" ;;
    json) OUT="${PROJECT_NAME}_dump.json" ;;
  esac
fi

OUT_REL=""    # the dump's own relative path — never dump the dump
if [[ "$STDOUT" -eq 0 && "$LIST_ONLY" -eq 0 && -n "$OUT" ]]; then
  [[ "$OUT" == */ ]] && die "output path '$OUT' ends with '/' — give a file path"
  if [[ -d "$OUT" ]]; then
    die "output path '$OUT' is an existing directory — give a file path"
  fi
  out_dir="$(dirname -- "$OUT")"
  if [[ ! -d "$out_dir" ]]; then
    mkdir -p -- "$out_dir" 2>/dev/null || die "cannot create output directory '$out_dir'"
    (( VERBOSE )) && inf "created output directory: $out_dir"
  fi
  OUT_REL="${OUT#./}"
fi

# ════════════════════════════════════════════════════════════════════════════
#  Small helpers
# ════════════════════════════════════════════════════════════════════════════
# v2: REPLY-style xml escape — call WITHOUT $( ) to avoid a fork per attribute.
xml_escape() {
  local s="$1"
  shopt -u patsub_replacement 2>/dev/null || true
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  REPLY="$s"
}

# JSON string encoder → REPLY (no fork on the fast path).
# Fast path (no control chars): only " and \ need escaping — pure bash.
# Slow path (control chars present — e.g. newlines in filenames): delegate to
# jq → python3 → awk exactly like v1.
json_escape() {
  local s="$1"
  if [[ "$s" =~ [[:cntrl:]] ]]; then
    if (( HAVE_JQ )); then
      REPLY="$(printf '%s' "$s" | jq -Rs .)"
    elif (( HAVE_PY3 )); then
      REPLY="$(printf '%s' "$s" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')"
    else
      REPLY="$(printf '"'; printf '%s' "$s" | awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r");
        if (NR>1) printf "\\n";
        printf "%s", $0
      }'; printf '"\n' | tr -d '\n')"
    fi
    return
  fi
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  REPLY="\"$s\""
}

# v2: when the python3 scanner ran in json mode it already encoded content;
# this is the fallback (jq per file → python3 per file → awk).
json_escape_file() {
  local f="$1" fsz
  if (( HAVE_JQ )); then
    jq -Rs . <"$f"
  elif (( HAVE_PY3 )); then
    python3 -c 'import sys, json; sys.stdout.write(json.dumps(sys.stdin.read()) + "\n")' <"$f"
  else
    fsz="$(file_size_bytes "$f")"
    LC_ALL=C awk -v fsz="$fsz" '
      BEGIN { printf "\"" }
      { raw += length($0) }
      {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r");
        gsub(/\010/,"\\b"); gsub(/\014/,"\\f");
        if (NR>1) printf "\\n";
        printf "%s", $0
      }
      END {
        if (NR>0 && fsz == raw + NR) printf "\\n";
        printf "\"\n"
      }' "$f"
  fi
}

file_size_bytes() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# v2 portability: NUL-delimited sort that works without GNU `sort -z`
# (BSD/macOS sort has no -z). Newlines inside records are escaped to \x01
# for the line-based sort and restored afterwards — a literal \x01 inside
# a filename is the accepted edge case (\x1f as field separator already is).
pdsort() {
  tr '\0\n' '\n\001' | sort "$@" | tr '\n\001' '\0\n'
}

# v2: pure-bash human size — no numfmt/awk fork per file.
# Matches `numfmt --to=iec --suffix=B` exactly (verified on boundary values):
# ceiling at display precision, unit carry past 1024, one decimal below 10.
human_size() {
  local b="${1:-0}" i=0 rem=0 whole frac t carry_rem
  local -a units=(B KB MB GB TB)
  if (( b < 1024 )); then
    printf '%dB' "$b"
    return 0
  fi
  whole=$b
  while (( whole >= 1024 && i < 4 )); do
    rem=$(( whole % 1024 ))
    whole=$(( whole / 1024 ))
    i=$(( i + 1 ))
  done
  # exact value in units[i] = whole + rem/1024
  if (( whole < 10 )); then
    # one decimal, ceiling: ceil((whole*1024 + rem) * 10 / 1024)
    t=$(( ( whole * 10240 + rem * 10 + 1023 ) / 1024 ))
    whole=$(( t / 10 ))
    frac=$(( t % 10 ))
  else
    (( rem > 0 )) && whole=$(( whole + 1 ))
    frac=0
  fi
  # rounding carried past 1024 → bump the unit (e.g. 1023.5KB → 1.0MB)
  if (( whole >= 1024 && i < 4 )); then
    carry_rem=$(( whole % 1024 ))
    whole=$(( whole / 1024 ))
    i=$(( i + 1 ))
    if (( whole < 10 )); then
      frac=$(( ( carry_rem * 10 + 512 ) / 1024 ))
      if (( frac >= 10 )); then whole=$(( whole + 1 )); frac=0; fi
    else
      frac=0
    fi
  fi
  if (( whole < 10 )); then
    printf '%d.%d%s' "$whole" "$frac" "${units[$i]}"
  else
    printf '%d%s' "$whole" "${units[$i]}"
  fi
}

# v1-compatible line count fallback (used only without python3, or for
# over-cap files): `grep -c ''` counts every line including an unterminated
# last line.
line_count() {
  local n
  n="$(LC_ALL=C grep -c '' -- "$1" 2>/dev/null)" || n=0
  printf '%s' "$n"
}

# ─── Language detection (lib/lang.sh, inlined + cached in v2) ────────────────
# v2: sets REPLY instead of echoing — call it WITHOUT $( ) to avoid a subshell
# fork per file; results are memoised per extension.
declare -A EXT_LANG_CACHE=()
lang_of() {
  local f="$1" base ext key
  base="${f##*/}"
  ext="${base##*.}"

  # Extensionless well-known files (checked by basename — cheap)
  case "$base" in
    Dockerfile|*.Dockerfile) REPLY=dockerfile; return ;;
    Makefile|makefile|GNUmakefile) REPLY=makefile; return ;;
    CMakeLists.txt|*.cmake) REPLY=cmake; return ;;
    .gitignore|.dockerignore|.npmignore|.gitattributes) REPLY=gitignore; return ;;
    .env|.env.*) REPLY=bash; return ;;
    .bashrc|.bash_profile|.bash_login|.bash_logout|.profile|.zshrc|.zprofile) REPLY=bash; return ;;
    .editorconfig|.gitconfig|.gitmodules|.npmrc) REPLY=ini; return ;;
    LICENSE|LICENCE|NOTICE|AUTHORS|CODEOWNERS) REPLY=text; return ;;
    *.service|*.socket|*.timer) REPLY=ini; return ;;
    *.lock) REPLY=text; return ;;
  esac

  key="${ext,,}"
  if [[ -n "${EXT_LANG_CACHE[$key]+x}" ]]; then
    REPLY="${EXT_LANG_CACHE[$key]}"
    return
  fi
  case "$key" in
    sh|bash|bats)  REPLY=bash ;;
    zsh)           REPLY=zsh ;;
    fish)          REPLY=fish ;;
    bat|cmd)       REPLY='batch' ;;
    ps1|psm1)      REPLY=powershell ;;
    py|pyi|pyw)    REPLY=python ;;
    js|mjs|cjs)    REPLY=javascript ;;
    ts|mts|cts)    REPLY=typescript ;;
    jsx)           REPLY=jsx ;;
    tsx)           REPLY=tsx ;;
    vue)           REPLY=vue ;;
    svelte)        REPLY=svelte ;;
    astro)         REPLY=astro ;;
    go)            REPLY=go ;;
    rs)            REPLY=rust ;;
    c|h)           REPLY=c ;;
    cpp|cc|cxx|hpp|hh|hxx) REPLY=cpp ;;
    cs)            REPLY=csharp ;;
    java)          REPLY=java ;;
    kt|kts)        REPLY=kotlin ;;
    swift)         REPLY=swift ;;
    rb|rake|gemspec) REPLY=ruby ;;
    php|phtml)     REPLY=php ;;
    pl|pm)         REPLY=perl ;;
    lua)           REPLY=lua ;;
    r|R)           REPLY=r ;;
    dart)          REPLY=dart ;;
    ex|exs)        REPLY=elixir ;;
    erl|hrl)       REPLY=erlang ;;
    hs)            REPLY=haskell ;;
    scala|sc)      REPLY=scala ;;
    clj|cljs|cljc) REPLY=clojure ;;
    elm)           REPLY=elm ;;
    jl)            REPLY=julia ;;
    zig)           REPLY=zig ;;
    sol)           REPLY=solidity ;;
    prisma)        REPLY=prisma ;;
    html|htm|xhtml) REPLY=html ;;
    css)           REPLY=css ;;
    scss|sass)     REPLY=scss ;;
    less)          REPLY=less ;;
    json|jsonc|json5) REPLY=json ;;
    ipynb|jsonl)   REPLY=json ;;
    yml|yaml)      REPLY=yaml ;;
    toml)          REPLY=toml ;;
    ini|conf|cfg|properties) REPLY=ini ;;
    md|markdown|mdx) REPLY=markdown ;;
    rst)           REPLY=rst ;;
    tex)           REPLY=latex ;;
    sql)           REPLY=sql ;;
    graphql|gql)   REPLY=graphql ;;
    proto)         REPLY=protobuf ;;
    xml|xsl|xslt)  REPLY=xml ;;
    svg)           REPLY=xml ;;
    csproj|props|plist|xaml|resx|wsdl) REPLY=xml ;;
    tf|tfvars)     REPLY=hcl ;;
    nix)           REPLY=nix ;;
    vim)           REPLY=vim ;;
    awk)           REPLY='awk' ;;
    sed)           REPLY='sed' ;;
    patch|diff)    REPLY='diff' ;;
    mm)            REPLY=objectivec ;;
    *)             REPLY=text ;;
  esac
  EXT_LANG_CACHE["$key"]="$REPLY"
}

# v2: binary-by-extension fast path (from lib/lang.sh) — applied BEFORE the
# scanner so obvious binaries are never even read.
binary_by_ext() {
  local base="${1##*/}"
  case "${base,,}" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.ico|*.icns|*.tiff|*.psd|*.ai) return 0 ;;
    *.pdf|*.zip|*.tar|*.gz|*.tgz|*.bz2|*.xz|*.zst|*.7z|*.rar)             return 0 ;;
    *.jar|*.war|*.class|*.so|*.dylib|*.dll|*.exe|*.bin|*.o|*.a|*.obj)     return 0 ;;
    *.wasm|*.woff|*.woff2|*.ttf|*.otf|*.eot)                              return 0 ;;
    *.mp3|*.wav|*.ogg|*.flac|*.mp4|*.mkv|*.avi|*.mov|*.webm)              return 0 ;;
    *.sqlite|*.sqlite3|*.db|*.pyc|*.pyo|*.pickle)                         return 0 ;;
    *.doc|*.docx|*.xls|*.xlsx|*.ppt|*.pptx|*.odt|*.ods|*.odp)             return 0 ;;
    *.xd|*.sketch|*.fig|*.blend|*.pcap|*.parquet)                         return 0 ;;
    *) return 1 ;;
  esac
}

# v2: grep -I fallback binary probe (only without python3)
is_binary_lazy() {
  [[ -f "$1" ]] || return 1
  [[ -s "$1" ]] || return 1
  LC_ALL=C grep -qI . "$1" 2>/dev/null || return 0
  return 1
}

# ─── Git helpers ─────────────────────────────────────────────────────────────
git_summary() {
  (( HAVE_GIT )) || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local branch sha dirty
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null \
            || git rev-parse --short HEAD 2>/dev/null \
            || printf 'detached')"
  sha="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    dirty="dirty"
  else
    dirty="clean"
  fi
  printf '%s @ %s (%s)' "$branch" "$sha" "$dirty"
}

# ─── v2: best-effort .gitignore support for NON-git directories ──────────────
# Subset: comments, blanks, negation (!), trailing / (dir), leading / (root
# anchored), plain globs (no ** support). Last matching pattern wins.
GITIGNORE_PATS=()
load_gitignore() {
  [[ -r "./.gitignore" ]] || return 0
  local line neg dir
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "" || "$line" == \#* ]] && continue
    neg=0; dir=0
    [[ "$line" == '!'* ]] && { neg=1; line="${line#!}"; }
    [[ "$line" == */ ]] && { dir=1; line="${line%/}"; }
    [[ -z "$line" ]] && continue
    GITIGNORE_PATS+=("${neg}${dir}:${line}")
  done < "./.gitignore"
}

gitignored() {
  local rel="$1" entry flags pat m result=0
  (( ${#GITIGNORE_PATS[@]} )) || return 1
  for entry in "${GITIGNORE_PATS[@]}"; do
    flags="${entry%%:*}"
    pat="${entry#*:}"
    m=0
    if [[ "${flags:1:1}" == "1" ]]; then
      # directory pattern: match the dir itself or anything under it
      # shellcheck disable=SC2254  # glob expansion in a case pattern is intended
      case "$rel" in $pat|$pat/*) m=1 ;; esac
    elif [[ "$pat" == /* ]]; then
      # root-anchored glob
      # shellcheck disable=SC2254
      case "$rel" in ${pat#/}) m=1 ;; esac
    elif [[ "$pat" == */* ]]; then
      # contains a slash → match any path suffix
      # shellcheck disable=SC2254
      case "/$rel" in */$pat) m=1 ;; esac
    else
      # no slash → match the whole path or any basename
      # shellcheck disable=SC2254
      case "$rel" in $pat) m=1 ;; esac
      # shellcheck disable=SC2254
      case "${rel##*/}" in $pat) m=1 ;; esac
    fi
    if (( m )); then
      if [[ "${flags:0:1}" == "1" ]]; then result=0; else result=1; fi
    fi
  done
  # shell convention: return 0 = "yes, ignore this file"
  if (( result )); then return 0; fi
  return 1
}

# ════════════════════════════════════════════════════════════════════════════
#  Collect candidate files
# ════════════════════════════════════════════════════════════════════════════
IN_GIT_REPO=0
if (( HAVE_GIT )) && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT_REPO=1
fi

collect_files() {
  if (( IN_GIT_REPO )); then
    if [[ -n "$SINCE" ]]; then
      {
        git diff --name-only -z --diff-filter=ACMR "$SINCE" 2>/dev/null || true
        git ls-files -z -o --exclude-standard 2>/dev/null || true
      } | pdsort -u
    else
      git ls-files -z -co --exclude-standard 2>/dev/null || true
    fi
  else
    find . -type f \
      ! -path "./.git/*" \
      ! -path "./node_modules/*" \
      ! -path "./.venv/*" ! -path "./venv/*" \
      ! -path "./__pycache__/*" \
      ! -path "./.pytest_cache/*" ! -path "./.mypy_cache/*" \
      ! -path "./dist/*" ! -path "./build/*" ! -path "./target/*" \
      ! -path "./.next/*" ! -path "./.nuxt/*" ! -path "./.svelte-kit/*" \
      ! -path "./.turbo/*" ! -path "./.cache/*" ! -path "./coverage/*" \
      ! -path "./.idea/*" ! -path "./.vscode/*" \
      ! -name "*.pyc" ! -name "*.o" ! -name "*.so" ! -name "*.class" \
      ! -name "*_dump.md" ! -name "*_dump.xml" ! -name "*_dump.json" \
      -print0 2>/dev/null || true
  fi
}

excluded() {
  local f="$1" rel="${1#./}" pat
  (( ${#EXCLUDES[@]} )) || return 1
  for pat in "${EXCLUDES[@]}"; do
    # shellcheck disable=SC2254  # glob expansion in a case pattern is intended
    case "$rel" in $pat) return 0 ;; esac
    # shellcheck disable=SC2254
    case "$f" in $pat) return 0 ;; esac
    # shellcheck disable=SC2254
    case "./$rel" in $pat) return 0 ;; esac
  done
  return 1
}

included() {
  local f="$1" rel="${1#./}" pat
  (( ${#INCLUDES[@]} )) || return 0
  for pat in "${INCLUDES[@]}"; do
    # shellcheck disable=SC2254
    case "$rel" in $pat) return 0 ;; esac
    # shellcheck disable=SC2254
    case "$f" in $pat) return 0 ;; esac
    # shellcheck disable=SC2254
    case "./$rel" in $pat) return 0 ;; esac
  done
  return 1
}

# Verbose bookkeeping: skip <path> <reason>
declare -A SKIPPED=()
SKIPPED_TOTAL=0
skip() {
  SKIPPED["$2"]=$(( ${SKIPPED["$2"]:-0} + 1 ))
  SKIPPED_TOTAL=$(( SKIPPED_TOTAL + 1 ))
  if (( VERBOSE )); then
    printf '  · skip: %s (%s)\n' "$1" "$2" >&2
  fi
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
#  v2 BATCH SCANNER — the big speedup.
#
#  ONE python3 process reads every candidate file once and emits NUL-delimited
#  records:   path \0 size \0 lines \0 flags \0 fence \0 [json-content]
#  flags:  1 = binary · 2 = needs trailing-newline pad · 4 = contains ]]>
#          8 = over scan-cap (measure lazily) · 16 = missing
#  Fallbacks: one GNU stat(1) batch (sizes), then lazy per-file probes.
# ════════════════════════════════════════════════════════════════════════════
declare -A SCAN_SIZES=() SCAN_LINES=() SCAN_FLAGS=() SCAN_FENCE=() SCAN_JSONC=()
SCANF_BINARY=1 SCANF_PADNL=2 SCANF_CDATA=4 SCANF_OVERCAP=8 SCANF_MISSING=16

SCAN_PY="$(cat <<'PY'
import sys, os, re, json
argv = sys.argv[1:]
maxb = int(argv[0]); mode = argv[1]; sent = argv[2]
out = sys.stdout.buffer
W = out.write
fence_re = re.compile(rb'`{3,}')
def emit(b):
    W(b); W(b'\x00')
for p in sys.stdin.buffer.read().split(b'\x00'):
    if not p:
        continue
    try:
        size = os.stat(p).st_size
        flags = 0; lines = 0; fence = 0; jc = None
        if size > 0:
            if size > maxb:
                flags = 8
            else:
                with open(p, 'rb') as fh:
                    data = fh.read()
                if b'\x00' in data:
                    flags = 1
                else:
                    lines = data.count(b'\n')
                    if data[-1:] != b'\n':
                        flags = 2; lines += 1
                    if b']]>' in data:
                        flags |= 4
                    fence = 0
                    for m in fence_re.finditer(data):
                        n = m.end() - m.start()
                        if n > fence: fence = n
                    if mode == 'json':
                        jc = json.dumps(data.decode('utf-8', 'replace'))
        emit(p)
        W(str(size).encode()); W(b'\x00')
        W(str(lines).encode()); W(b'\x00')
        W(str(flags).encode()); W(b'\x00')
        W(str(fence).encode()); W(b'\x00')
        if mode == 'json':
            W(jc.encode() if jc is not None else b'""'); W(b'\x00')
    except OSError:
        emit(p); W(b'-1'); W(b'\x00'); W(b'0'); W(b'\x00')
        W(b'16'); W(b'\x00'); W(b'0'); W(b'\x00')
W(sent.encode()); W(b'\x00')
out.flush()
PY
)"

# Effective content-scan cap: honour --max-size, but always scan up to 32MB
# so "unlimited" mode still works; beyond the cap files are marked
# SCANF_OVERCAP and measured lazily if they actually make it into the dump.
scan_cap_bytes() {
  local cap=$(( 32 * 1024 * 1024 ))
  if (( MAX_FILE_SIZE > 0 )); then
    local mx=$(( MAX_FILE_SIZE * 1024 ))
    (( mx > cap )) && cap=$mx
  fi
  printf '%s' "$cap"
}

# scan_all PATH…  → fills SCAN_* (sizes always; the rest on the python path)
scan_all() {
  local -a cand=("$@")
  (( ${#cand[@]} )) || return 0
  local p sz ln fl fc rel jc SENT="PROJDUMP_SCAN_DONE_$$_$RANDOM"

  if (( HAVE_PY3 )); then
    local mode=none done_seen=0
    [[ "$FORMAT" == "json" ]] && mode=json
    # read -r -d '' keeps embedded newlines; fields are NUL-delimited.
    # The sentinel is a single NUL-terminated field: when it arrives, the
    # NEXT read in this chain hits EOF and the loop exits — so the sentinel
    # check happens after the loop (p keeps the last-read value).
    while IFS= read -r -d '' p && IFS= read -r -d '' sz && IFS= read -r -d '' ln \
       && IFS= read -r -d '' fl && IFS= read -r -d '' fc; do
      if [[ "$p" == "$SENT" ]]; then done_seen=1; break; fi
      if [[ "$sz" == "-1" ]]; then fl=$(( fl | SCANF_MISSING )); sz=0; fi
      rel="${p#./}"
      SCAN_SIZES["$rel"]="$sz"
      SCAN_LINES["$rel"]="$ln"
      SCAN_FLAGS["$rel"]="$fl"
      SCAN_FENCE["$rel"]="$fc"
      if [[ "$mode" == "json" ]]; then
        IFS= read -r -d '' jc || true
        SCAN_JSONC["$rel"]="$jc"
      fi
    done < <(printf '%s\0' "${cand[@]}" | python3 -c "$SCAN_PY" "$(scan_cap_bytes)" "$mode" "$SENT" 2>/dev/null)
    [[ "${p:-}" == "$SENT" ]] && done_seen=1
    (( done_seen )) || die "internal error: python3 scanner failed — please report this bug"
    return 0
  fi

  # ── fallback 1: one GNU stat batch for all sizes ──
  if (( HAVE_GNU_STAT )); then
    local got=0
    while IFS= read -r -d '' sz && IFS= read -r -d '' p; do
      got=$(( got + 1 ))
      rel="${p#./}"
      SCAN_SIZES["$rel"]="$sz"
      SCAN_FLAGS["$rel"]=0
    done < <(printf '%s\0' "${cand[@]}" | xargs -0 -r stat --printf '%s\0%n\0' 2>/dev/null)
    if (( got == ${#cand[@]} )); then
      return 0   # sizes known; lines/binary/fence measured lazily
    fi
    # partial stat output (vanished files?) → fall through to per-file
  fi

  # ── fallback 2: per-file size probes (v1 behaviour — correct, slower) ──
  local f
  for f in "${cand[@]}"; do
    rel="${f#./}"
    SCAN_SIZES["$rel"]="$(file_size_bytes "$f")"
    SCAN_FLAGS["$rel"]=0
  done
}

# Lazy per-file measurement for the fallback paths (no python3) and for
# over-cap files that still made it into the dump. Always recomputes lines +
# fence (it is only ever called for files that need it).
measure_lazy() {
  local f="$1" rel="${1#./}" fl=0 longest=0 run
  SCAN_LINES["$rel"]="$(line_count "$f")"
  if binary_by_ext "$f" || is_binary_lazy "$f"; then
    fl=$(( fl | SCANF_BINARY ))
  fi
  # trailing-newline pad flag
  if [[ -s "$f" && -n "$(tail -c1 -- "$f" 2>/dev/null || printf x)" ]]; then
    fl=$(( fl | SCANF_PADNL ))
  fi
  # CDATA marker
  if LC_ALL=C grep -q ']]>' -- "$f" 2>/dev/null; then
    fl=$(( fl | SCANF_CDATA ))
  fi
  SCAN_FLAGS["$rel"]="$fl"
  # fence: longest backtick run ≥ 3 (a shorter run can't break a 3-fence)
  while IFS= read -r run; do
    (( ${#run} > longest )) && longest=${#run}
  done < <(LC_ALL=C grep -o '`\{3,\}' -- "$f" 2>/dev/null || true)
  SCAN_FENCE["$rel"]="$longest"
}

# ════════════════════════════════════════════════════════════════════════════
#  Token estimation (v2: weighted per language class)
#  tokens = ceil(bytes × 10 / R), R = 23 minified · 32 data · 35 code · 40 prose
# ════════════════════════════════════════════════════════════════════════════
token_ratio() { # $1 = rel path → REPLY (no fork — runs per file)
  local base="${1##*/}" ext
  ext="${base##*.}"; ext="${ext,,}"
  case "$base" in
    *.min.js|*.min.css|*.bundle.js|*.map) REPLY=23; return ;;
  esac
  case "$ext" in
    json|csv|tsv|xml|html|svg|yaml|yml|toml) REPLY=32; return ;;
    md|markdown|mdx|txt|rst|tex)             REPLY=40; return ;;
    *)                                       REPLY=35 ;;
  esac
}

tokens_of() { # $1 = rel path → REPLY (estimated tokens, ceil)
  token_ratio "$1"
  REPLY=$(( ( ${SCAN_SIZES["$1"]:-0} * 10 + REPLY - 1 ) / REPLY ))
}

# ════════════════════════════════════════════════════════════════════════════
#  Filter pipeline (reason order mirrors v1: regular → output → excluded →
#  included → ext filter → [gitignore] → too large → binary)
# ════════════════════════════════════════════════════════════════════════════
declare -a CAND=() FILES=()
declare -A SIZES=() LINES=() LANG_OF=()
declare -A L_FILES=() L_LINES=() L_BYTES=()
declare -a LANG_ORDER=()
STAT_FILES=0 STAT_LINES=0 STAT_BYTES=0 STAT_TOKENS=0

EXT_ALLOWED=()
if [[ -n "$EXT_FILTER" ]]; then
  IFS=',' read -ra _raw_ext <<<"$EXT_FILTER"
  for a in "${_raw_ext[@]}"; do
    a="${a//[[:space:]]/}"; a="${a#.}"; a="${a,,}"
    [[ -n "$a" ]] && EXT_ALLOWED+=("$a")
  done
fi

prepare_files() {
  local f rel base ext a match

  # Phase 0 — collect
  while IFS= read -r -d '' f; do
    CAND+=("$f")
  done < <(collect_files)

  # Phase 1 — forkless pre-filters so the scanner only sees plausible files
  local -a pre=()
  for f in "${CAND[@]}"; do
    rel="${f#./}"
    if [[ ! -f "$f" ]]; then skip "$rel" "not a regular file"; continue; fi
    if [[ -n "$OUT_REL" && "$rel" == "$OUT_REL" ]]; then skip "$rel" "output file"; continue; fi
    if (( ${#EXCLUDES[@]} )) && excluded "$f"; then skip "$rel" "excluded"; continue; fi
    if (( ${#INCLUDES[@]} )) && ! included "$f"; then skip "$rel" "not included"; continue; fi
    if (( ${#EXT_ALLOWED[@]} )); then
      base="${rel##*/}"
      match=0
      if [[ "$base" == *.* ]]; then
        ext="${base##*.}"; ext="${ext,,}"
        for a in "${EXT_ALLOWED[@]}"; do
          [[ "$ext" == "$a" ]] && { match=1; break; }
        done
      fi
      if (( ! match )); then skip "$rel" "extension filter"; continue; fi
    fi
    # obvious binaries never reach the scanner (also keeps --max-size honest)
    if binary_by_ext "$f"; then skip "$rel" "binary"; continue; fi
    pre+=("$f")
  done

  # Phase 2 — ONE batch scan
  if (( ${#pre[@]} )); then
    scan_all "${pre[@]}"
  fi

  # Phase 3 — size / binary filters using the scanned data
  local fl
  for f in "${pre[@]}"; do
    rel="${f#./}"
    fl="${SCAN_FLAGS["$rel"]:-0}"
    if (( fl & SCANF_MISSING )); then skip "$rel" "not a regular file"; continue; fi
    if (( MAX_FILE_SIZE > 0 )) && (( ${SCAN_SIZES["$rel"]:-0} > MAX_FILE_SIZE * 1024 )); then
      skip "$rel" "too large"; continue
    fi
    if (( fl & SCANF_BINARY )); then skip "$rel" "binary"; continue; fi
    if (( ! IN_GIT_REPO )) && (( ${#GITIGNORE_PATS[@]} )) && gitignored "$rel"; then
      skip "$rel" "gitignored"; continue
    fi
    SIZES["$rel"]="${SCAN_SIZES["$rel"]:-0}"
    # fallback paths / over-cap survivors get measured lazily
    if (( fl & SCANF_OVERCAP )) || [[ -z "${SCAN_LINES[$rel]+x}" ]]; then
      measure_lazy "$f"
      fl="${SCAN_FLAGS["$rel"]:-0}"
    fi
    LINES["$rel"]="${SCAN_LINES[$rel]:-0}"
    lang_of "$f"; LANG_OF["$rel"]="$REPLY"
    FILES+=("$f")
  done

  apply_sort
  apply_budget
  compute_lang_stats
  compute_totals
  return 0
}

compute_lang_stats() {
  # v2: single pass — accumulates the language buckets AND the totals
  # (compute_totals used to iterate FILES a second time).
  local f rel lang l
  LANG_ORDER=()
  L_FILES=(); L_LINES=(); L_BYTES=()
  STAT_LINES=0
  STAT_BYTES=0
  STAT_TOKENS=0
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    lang="${LANG_OF["$rel"]:-text}"
    L_FILES["$lang"]=$(( ${L_FILES["$lang"]:-0} + 1 ))
    L_LINES["$lang"]=$(( ${L_LINES["$lang"]:-0} + ${LINES["$rel"]:-0} ))
    L_BYTES["$lang"]=$(( ${L_BYTES["$lang"]:-0} + ${SIZES["$rel"]:-0} ))
    STAT_LINES=$(( STAT_LINES + ${LINES["$rel"]:-0} ))
    STAT_BYTES=$(( STAT_BYTES + ${SIZES["$rel"]:-0} ))
    tokens_of "$rel"
    STAT_TOKENS=$(( STAT_TOKENS + REPLY ))
  done
  while IFS=$'\t' read -r _ l; do
    LANG_ORDER+=("$l")
  done < <(
    for l in "${!L_FILES[@]}"; do
      printf '%012d\t%s\n' "${L_BYTES[$l]:-0}" "$l"
    done | LC_ALL=C sort -r
  )
  return 0
}

# v2: totals are accumulated by compute_lang_stats — this now only fills
# STAT_FILES (kept for --list and the part-report path).
compute_totals() {
  STAT_FILES=${#FILES[@]}
  return 0
}

# ─── Ordering & budget ───────────────────────────────────────────────────────
apply_sort() {
  (( ${#FILES[@]} > 1 )) || return 0
  local -a sflags=()
  if [[ "$SORT_KEY" == "size-desc" ]]; then
    sflags=('-k1,1r')   # key desc, ties (same size) stay name-ascending
  fi
  local f rel key ext
  local -a ordered=()
  while IFS= read -r -d '' rec; do
    ordered+=("${rec#*$'\t'}")
  done < <(
    while IFS= read -r -d '' f; do
      rel="${f#./}"
      case "$SORT_KEY" in
        size|size-desc) printf -v key '%012d' "${SIZES["$rel"]:-0}" ;;   # printf -v: no fork
        ext)
          ext="${rel##*/}"
          if [[ "$ext" == *.* ]]; then ext="${ext##*.}"; else ext=""; fi
          key="${ext,,}"
          ;;
        *) key="" ;;
      esac
      printf '%s\t%s\0' "$key" "$rel"
    done < <(printf '%s\0' "${FILES[@]}") | pdsort "${sflags[@]}"
  )
  FILES=("${ordered[@]}")
  return 0
}

apply_budget() {
  (( BUDGET > 0 )) || return 0
  local -a keep=()
  local f rel total=0 n=0
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    tokens_of "$rel"
    if (( n > 0 && total + REPLY > BUDGET )); then
      skip "$rel" "over token budget"
      continue
    fi
    total=$(( total + REPLY ))
    n=$(( n + 1 ))
    keep+=("$f")
  done
  FILES=("${keep[@]}")
  return 0
}

# ─── Split planning (v2): partition FILES in order, each part ≤ SPLIT_TOK ────
FULL_FILES=()
PART_BOUNDS=()
PART_TOTAL=1 PART_NUM=0
plan_split() {
  if (( SPLIT_TOK == 0 )); then
    PART_BOUNDS=("${#FILES[@]}")
    PART_TOTAL=1
    return 0
  fi
  FULL_FILES=("${FILES[@]}")
  PART_BOUNDS=()
  local f rel total=0 n=0 i=0
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    tokens_of "$rel"
    if (( n > 0 && total + REPLY > SPLIT_TOK )); then
      PART_BOUNDS+=("$i")
      total=0; n=0
    fi
    total=$(( total + REPLY ))
    n=$(( n + 1 ))
    i=$(( i + 1 ))
  done
  (( n > 0 )) && PART_BOUNDS+=("$i")
  PART_TOTAL=${#PART_BOUNDS[@]}
  (( PART_TOTAL > 0 )) || PART_TOTAL=1
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
#  Tree rendering (v2: pure bash — tree(1) is no longer required)
#  Dirs first (case-insensitive), then files; `…` marks a collapsed dir when
#  --tree-depth is reached.
# ════════════════════════════════════════════════════════════════════════════
declare -A T_DIRS=() T_FILES=()
TREE_OUT=()
# bash 5.2 rejects empty assoc subscripts — use a control char as the root key
readonly TREE_ROOT_KEY=$'\x01'

tree_key() { # "" → TREE_ROOT_KEY
  if [[ -z "$1" ]]; then printf '%s' "$TREE_ROOT_KEY"; else printf '%s' "$1"; fi
}

build_tree_map() {
  # NOTE: records are `parent <US> type <US> name`, NUL-terminated, where
  # US = \x1f (unit separator). A TAB would be gobbled as leading IFS
  # whitespace for root children (parent=""), shifting every field.
  local p rest name isdir dir parent type child key
  T_DIRS=(); T_FILES=()
  while IFS=$'\x1f' read -r -d '' parent type child; do
    # inline tree_key (no subshell — this runs once per path component)
    if [[ -z "$parent" ]]; then key="$TREE_ROOT_KEY"; else key="$parent"; fi
    if [[ "$type" == "D" ]]; then
      T_DIRS["$key"]+="${child}"$'\n'
    else
      T_FILES["$key"]+="${child}"$'\n'
    fi
  done < <(
    for p in "$@"; do
      dir=""; rest="$p"
      while [[ -n "$rest" ]]; do
        name="${rest%%/*}"
        if [[ "$rest" == */* ]]; then
          rest="${rest#*/}"; isdir="D"
        else
          rest=""; isdir="F"
        fi
        printf '%s\x1f%s\x1f%s\0' "$dir" "$isdir" "$name"
        if [[ "$isdir" == "D" ]]; then
          if [[ -z "$dir" ]]; then dir="$name"; else dir="$dir/$name"; fi
        fi
      done
    done | LC_ALL=C pdsort -fu -t$'\x1f' -k1,1 -k2,2 -k3,3
  )
}

render_tree() {
  TREE_OUT=(".")
  (( ${#@} )) || return 0
  build_tree_map "$@"
  tree_render_dir "" "" 1
}

tree_render_dir() { # $1 dir, $2 prefix, $3 level (1 = children of root)
  local dir="$1" prefix="$2" lvl="$3"
  local key list child
  if [[ -z "$dir" ]]; then key="$TREE_ROOT_KEY"; else key="$dir"; fi
  local -a kids=()
  # v2: split the newline-joined lists with pure string ops — a herestring
  # (<<<) would create a temp file per directory.
  list="${T_DIRS[$key]:-}"
  while [[ -n "$list" ]]; do
    child="${list%%$'\n'*}"        # text before the FIRST newline
    list="${list#"$child"$'\n'}"
    kids+=("D$child")
  done
  list="${T_FILES[$key]:-}"
  while [[ -n "$list" ]]; do
    child="${list%%$'\n'*}"
    list="${list#"$child"$'\n'}"
    kids+=("F$child")
  done
  local count=${#kids[@]} i k type name conn cont np
  for ((i = 0; i < count; i++)); do
    k="${kids[$i]}"
    type="${k:0:1}"
    name="${k:1}"
    conn="├── "
    cont="│   "
    if (( i == count - 1 )); then
      conn="└── "
      cont="    "
    fi
    TREE_OUT+=("${prefix}${conn}${name}")
    if [[ "$type" == "D" ]]; then
      if (( TREE_DEPTH > 0 && lvl >= TREE_DEPTH )); then
        TREE_OUT+=("${prefix}${cont}…")
      else
        if [[ -z "$dir" ]]; then np="$name"; else np="$dir/$name"; fi
        tree_render_dir "$np" "${prefix}${cont}" $(( lvl + 1 ))
      fi
    fi
  done
}

# ════════════════════════════════════════════════════════════════════════════
#  Writers
# ════════════════════════════════════════════════════════════════════════════
fence_for() { # $1 = rel → REPLY
  local need=$(( ${SCAN_FENCE["$1"]:-0} + 1 ))
  (( need < 3 )) && need=3
  local fence=""
  while (( ${#fence} < need )); do fence+='`'; done
  REPLY="$fence"
}

write_header_md() {
  echo "# 📦 ${PROJECT_NAME} — Project Dump"
  echo
  echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')  "
  echo "**Path:** \`$PWD\`  "
  echo "**Host:** $(hostname 2>/dev/null || echo unknown)  "
  echo "**Tool:** ${SCRIPT_NAME} v${SCRIPT_VERSION}  "
  local git_info
  if git_info="$(git_summary)"; then
    echo "**Git:** \`$git_info\`  "
  fi
  if [[ -n "$SINCE" ]]; then
    echo "**Scope:** files changed since \`$SINCE\`  "
  fi
  if (( PART_TOTAL > 1 )); then
    echo "**Part:** ${PART_NUM}/${PART_TOTAL}  "
  fi
  echo
  echo "---"
  echo
  if [[ -n "$NOTE" ]]; then
    echo "## 📝 Note for the AI"
    echo
    printf '%s\n' "$NOTE"
    echo
    echo "---"
    echo
  fi
}

write_tree_md() {
  if [[ "$SHOW_TREE" != "1" ]]; then return 0; fi
  echo "## 📁 Directory Tree"
  echo
  echo '```'
  if (( ${#FILES[@]} )); then
    local l
    render_tree "${FILES[@]#./}"
    for l in "${TREE_OUT[@]}"; do
      printf '%s\n' "$l"
    done
  else
    echo "(no files)"
  fi
  echo '```'
  echo
  echo "---"
  echo
}

write_file_md() {
  local f="$1" rel="${1#./}"
  fence_for "$rel"
  echo "### \`$rel\`"
  echo
  echo "${REPLY}${LANG_OF["$rel"]:-text}"
  cat -- "$f"
  # only pad when the file has no trailing newline, so we don't invent a blank line
  if (( ${SCAN_FLAGS["$rel"]:-0} & SCANF_PADNL )); then echo; fi
  echo "$REPLY"
  echo
  echo "<sub>${LINES["$rel"]:-0} lines · $(human_size "${SIZES["$rel"]:-0}")</sub>"
  echo
}

write_commits_md() {
  (( ${#COMMITS[@]} )) || return 0
  echo
  echo "### 📜 Recent commits"
  echo
  # a commit subject could contain backticks — grow the fence like file fences
  local c run longest=0 fence='```' re='`+'
  for c in "${COMMITS[@]}"; do
    while [[ "$c" =~ $re ]]; do
      run="${BASH_REMATCH[0]}"
      (( ${#run} > longest )) && longest=${#run}
      c="${c#"$run"}"
    done
  done
  if (( longest + 1 > 3 )); then
    fence=""
    while (( ${#fence} < longest + 1 )); do fence+='`'; done
  fi
  echo "$fence"
  printf '%s\n' "${COMMITS[@]}"
  echo "$fence"
}

write_stats_md() {
  echo "---"
  echo
  echo "## 📊 Summary"
  echo
  echo "| Files | Lines | Size |"
  echo "|---:|---:|---:|"
  echo "| ${STAT_FILES} | ${STAT_LINES} | $(human_size "$STAT_BYTES") |"
  echo
  echo "> Roughly ${STAT_TOKENS} tokens (weighted per language)"

  if (( ${#LANG_ORDER[@]} )); then
    echo
    echo "### 🗂️ Languages"
    echo
    echo "| Language | Files | Lines | Size |"
    echo "|---|---:|---:|---:|"
    local l
    for l in "${LANG_ORDER[@]}"; do
      printf '| %s | %s | %s | %s |\n' \
        "$l" "${L_FILES["$l"]:-0}" "${L_LINES["$l"]:-0}" "$(human_size "${L_BYTES["$l"]:-0}")"
    done
  fi

  if (( STAT_FILES > 3 )); then
    echo
    echo "### 🐘 Largest files"
    echo
    local f rel
    local -a top=()
    # NUL-separated records, so paths with newlines survive intact
    while IFS= read -r -d '' rec; do
      if (( ${#top[@]} >= 5 )); then break; fi
      top+=("${rec#*$'\t'}")
    done < <(
      for f in "${FILES[@]}"; do
        rel="${f#./}"
        printf '%012d\t%s\0' "${SIZES["$rel"]:-0}" "$rel"
      done | LC_ALL=C pdsort -k1,1r
    )
    for rel in "${top[@]}"; do
      # shellcheck disable=SC2016  # literal markdown backticks are intentional
      printf -- '- `%s` — %s lines · %s\n' \
        "$rel" "${LINES["$rel"]:-0}" "$(human_size "${SIZES["$rel"]:-0}")"
    done
  fi

  write_commits_md
}

# ─── Dry-run listing ─────────────────────────────────────────────────────────
run_list() {
  local f rel
  if (( ! QUIET )); then
    printf '   SIZE  LINES  PATH\n'
  fi
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    printf '%7s %6s  %s\n' \
      "$(human_size "${SIZES["$rel"]:-0}")" "${LINES["$rel"]:-0}" "$rel"
  done
  if (( ! QUIET )); then
    printf '%7s %6s  (%d files, ~%s tokens)\n' \
      "$(human_size "$STAT_BYTES")" "$STAT_LINES" "$STAT_FILES" "$STAT_TOKENS"
  fi
  return 0
}

# ─── Dump writers ────────────────────────────────────────────────────────────
run_dump() {
  local f rel l git_info first c jc

  case "$FORMAT" in
    md)
      write_header_md
      write_tree_md
      echo "## 📄 Source Files"
      echo
      if (( ${#FILES[@]} == 0 )); then
        echo "_No files matched._"
        echo
      else
        for f in "${FILES[@]}"; do
          write_file_md "$f"
        done
      fi
      write_stats_md
      ;;
    xml)
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      xml_escape "$PROJECT_NAME"; local x_name="$REPLY"
      xml_escape "$PWD"; local x_path="$REPLY"
      xml_escape "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; local x_gen="$REPLY"
      xml_escape "$SCRIPT_NAME v$SCRIPT_VERSION"; local x_tool="$REPLY"
      printf '<project name="%s" path="%s" generated="%s" tool="%s"' \
        "$x_name" "$x_path" "$x_gen" "$x_tool"
      if git_info="$(git_summary)"; then
        xml_escape "$git_info"
        printf ' git="%s"' "$REPLY"
      fi
      if [[ -n "$SINCE" ]]; then
        xml_escape "$SINCE"
        printf ' since="%s"' "$REPLY"
      fi
      if (( PART_TOTAL > 1 )); then
        printf ' part="%s/%s"' "$PART_NUM" "$PART_TOTAL"
      fi
      printf '>\n'
      if [[ -n "$NOTE" ]]; then
        echo '  <note><![CDATA['
        printf '%s\n' "$NOTE" | sed 's/]]>/]]]]><![CDATA[>/g'
        echo '  ]]></note>'
      fi
      if [[ "$SHOW_TREE" == "1" ]]; then
        echo "  <tree><![CDATA["
        if (( ${#FILES[@]} )); then
          printf '%s\n' "${FILES[@]#./}" | sort -u
        fi
        echo "  ]]></tree>"
      fi
      for f in "${FILES[@]}"; do
        rel="${f#./}"
        xml_escape "$rel"; local x_rel="$REPLY"
        xml_escape "${LANG_OF["$rel"]:-text}"; local x_lang="$REPLY"
        printf '  <file path="%s" lang="%s" lines="%s" bytes="%s">\n' \
          "$x_rel" "$x_lang" \
          "${LINES["$rel"]:-0}" "${SIZES["$rel"]:-0}"
        echo "    <![CDATA["
        # A literal ]]> inside the file would close the CDATA section early,
        # so split it: "]]" + "><![CDATA[" + ">"
        if (( ${SCAN_FLAGS["$rel"]:-0} & SCANF_CDATA )); then
          sed 's/]]>/]]]]><![CDATA[>/g' -- "$f"
        else
          cat -- "$f"
        fi
        echo
        echo "    ]]>"
        echo "  </file>"
      done
      if (( ${#COMMITS[@]} )); then
        echo "  <commits count=\"${#COMMITS[@]}\">"
        for c in "${COMMITS[@]}"; do
          xml_escape "$c"
          printf '    <commit>%s</commit>\n' "$REPLY"
        done
        echo "  </commits>"
      fi
      printf '  <stats files="%s" lines="%s" bytes="%s" tokens="%s">\n' \
        "$STAT_FILES" "$STAT_LINES" "$STAT_BYTES" "$STAT_TOKENS"
      for l in "${LANG_ORDER[@]}"; do
        xml_escape "$l"; local x_lang2="$REPLY"
        printf '    <language name="%s" files="%s" lines="%s" bytes="%s"/>\n' \
          "$x_lang2" "${L_FILES["$l"]:-0}" "${L_LINES["$l"]:-0}" "${L_BYTES["$l"]:-0}"
      done
      echo '  </stats>'
      echo "</project>"
      ;;
    json)
      json_escape "$PROJECT_NAME"; local j_name="$REPLY"
      json_escape "$PWD"; local j_path="$REPLY"
      json_escape "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; local j_gen="$REPLY"
      json_escape "$SCRIPT_NAME v$SCRIPT_VERSION"; local j_tool="$REPLY"
      printf '{\n'
      printf '  "project": %s,\n'    "$j_name"
      printf '  "path": %s,\n'       "$j_path"
      printf '  "generated": %s,\n'  "$j_gen"
      printf '  "tool": %s,\n'       "$j_tool"
      if git_info="$(git_summary)"; then
        json_escape "$git_info"
        printf '  "git": %s,\n' "$REPLY"
      fi
      if [[ -n "$SINCE" ]]; then
        json_escape "$SINCE"
        printf '  "since": %s,\n' "$REPLY"
      fi
      if (( PART_TOTAL > 1 )); then
        json_escape "${PART_NUM}/${PART_TOTAL}"
        printf '  "part": %s,\n' "$REPLY"
      fi
      if [[ -n "$NOTE" ]]; then
        json_escape "$NOTE"
        printf '  "note": %s,\n' "$REPLY"
      fi
      printf '  "files": ['
      first=1
      for f in "${FILES[@]}"; do
        rel="${f#./}"
        (( first )) || printf ',\n'
        first=0
        # v2: prefer the scanner's pre-encoded content; fall back to
        # jq/python3/awk per file when the scanner couldn't encode.
        jc="${SCAN_JSONC[$rel]:-}"
        if [[ -z "$jc" ]]; then
          jc="$(json_escape_file "$f")"
        fi
        json_escape "$rel"; local j_rel="$REPLY"
        json_escape "${LANG_OF["$rel"]:-text}"; local j_lang="$REPLY"
        printf '\n    {"path": %s, "lang": %s, "lines": %s, "bytes": %s, "content": %s}' \
          "$j_rel" \
          "$j_lang" \
          "${LINES["$rel"]:-0}" \
          "${SIZES["$rel"]:-0}" \
          "$jc"
      done
      printf '\n  ],\n'
      if (( ${#COMMITS[@]} )); then
        printf '  "commits": ['
        first=1
        for c in "${COMMITS[@]}"; do
          (( first )) || printf ', '
          first=0
          json_escape "$c"
          printf '%s' "$REPLY"
        done
        printf '],\n'
      fi
      printf '  "stats": {"files": %s, "lines": %s, "bytes": %s, "tokens": %s, "languages": {' \
        "$STAT_FILES" "$STAT_LINES" "$STAT_BYTES" "$STAT_TOKENS"
      first=1
      for l in "${LANG_ORDER[@]}"; do
        (( first )) || printf ', '
        first=0
        printf '"%s": {"files": %s, "lines": %s, "bytes": %s}' \
          "$l" "${L_FILES["$l"]:-0}" "${L_LINES["$l"]:-0}" "${L_BYTES["$l"]:-0}"
      done
      printf '}}\n'
      printf '}\n'
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
#  Run
# ════════════════════════════════════════════════════════════════════════════
TMP_OUT=""
cleanup() {
  [[ -n "$TMP_OUT" ]] && rm -f -- "$TMP_OUT"
  # bash uses the EXIT trap's last status as the script's exit status —
  # without this, a successful run would exit 1 whenever TMP_OUT was empty.
  return 0
}
trap cleanup EXIT

# Resolve JOBS (currently used by the GNU-stat fallback batch)
JOBS_RESOLVED="$JOBS"
if (( JOBS_RESOLVED == 0 )); then
  JOBS_RESOLVED="$(nproc 2>/dev/null || echo 4)"
  (( JOBS_RESOLVED > 8 )) && JOBS_RESOLVED=8
  (( JOBS_RESOLVED < 1 )) && JOBS_RESOLVED=1
fi

# Non-git mode: best-effort .gitignore
if (( ! IN_GIT_REPO )); then
  load_gitignore
  if (( ${#GITIGNORE_PATS[@]} )) && (( VERBOSE )); then
    inf "→ non-git mode: applying .gitignore (best-effort, ${#GITIGNORE_PATS[@]} patterns)"
  fi
fi

# git-log capture (once)
declare -a COMMITS=()
if (( GIT_LOG > 0 )); then
  if (( ! HAVE_GIT )); then
    die "--git-log requires git"
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "--git-log must run inside a git repository"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && COMMITS+=("$line")
  done < <(git log --oneline -n "$GIT_LOG" 2>/dev/null || true)
fi

prepare_files
plan_split

if (( VERBOSE )); then
  inf "→ ${STAT_FILES} files selected · ~${STAT_TOKENS} tokens"
  if (( PART_TOTAL > 1 )); then
    inf "→ split into ${PART_TOTAL} parts (≤ ${SPLIT_TOK} tokens each)"
  fi
  [[ -n "$CONFIG_LOADED_FROM" ]] && inf "→ config: ${CONFIG_LOADED_FROM}"
fi

if (( LIST_ONLY )); then
  run_list
  exit 0
fi

if (( VERBOSE )) && (( SKIPPED_TOTAL > 0 )); then
  inf "→ ${SKIPPED_TOTAL} files skipped (see above)"
fi

write_part() { # $1 = target file ('-' = stdout); uses current FILES + stats
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/projdump.out.XXXXXX")"
  run_dump >"$tmp"
  if [[ "$1" == "-" ]]; then
    cat -- "$tmp"
    rm -f -- "$tmp"
  else
    mv -- "$tmp" "$1"
  fi
}

if (( PART_TOTAL > 1 )); then
  stem="${OUT%.*}"
  ext="${OUT##*.}"
  if [[ "$stem" == "$OUT" ]]; then ext=""; else ext=".$ext"; fi
  PART_FILES=()
  prev=0
  idx=1
  for end in "${PART_BOUNDS[@]}"; do
    FILES=("${FULL_FILES[@]:prev:end-prev}")
    compute_lang_stats
    compute_totals
    PART_NUM="$idx"
    outf="${stem}.part${idx}${ext}"
    write_part "$outf"
    PART_FILES+=("$outf")
    (( VERBOSE )) && inf "  → part ${idx}/${PART_TOTAL}: $outf ($(human_size "$(file_size_bytes "$outf")"))"
    prev="$end"
    idx=$(( idx + 1 ))
  done
  # restore full stats for the report
  FILES=("${FULL_FILES[@]}")
  compute_lang_stats
  compute_totals
else
  PART_NUM=1
  if (( STDOUT )); then
    write_part "-"
  else
    write_part "$OUT"
  fi
fi

# ─── Report ──────────────────────────────────────────────────────────────────
if (( ! QUIET )); then
  ok "✓ ${STAT_FILES} files · ${STAT_LINES} lines · $(human_size "$STAT_BYTES") · ~${STAT_TOKENS} tokens"
  if (( PART_TOTAL > 1 )); then
    ok "✓ ${PART_TOTAL} parts: ${PART_FILES[*]}"
  elif (( ! STDOUT )); then
    ok "✓ $OUT — $(human_size "$(file_size_bytes "$OUT")") · $(line_count "$OUT") lines"
  fi
  if (( SKIPPED_TOTAL > 0 )); then
    inf "  (${SKIPPED_TOTAL} files skipped — rerun with --verbose for details)"
  fi
fi

# ─── Clipboard ───────────────────────────────────────────────────────────────
copy_to_clipboard() {
  local src="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$src"
  elif command -v wl-copy >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    wl-copy <"$src"
  elif command -v clip.exe >/dev/null 2>&1; then
    clip.exe <"$src"                       # WSL
  elif command -v putclip >/dev/null 2>&1; then
    putclip <"$src"                         # Cygwin
  elif command -v xclip >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xclip -selection clipboard <"$src"
  elif command -v xsel >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xsel --clipboard --input <"$src"
  else
    return 1
  fi
}

if [[ "$COPY_MODE" != "no" && "$STDOUT" -eq 0 ]]; then
  if (( PART_TOTAL > 1 )); then
    copy_to_clipboard "${PART_FILES[0]}" 2>/dev/null \
      && ok "✓ Copied part 1/${PART_TOTAL} to clipboard" || true
  else
    copy_to_clipboard "$OUT" 2>/dev/null && ok "✓ Copied to clipboard" || true
  fi
fi
