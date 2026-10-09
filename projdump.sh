#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump — dump an entire codebase into a single LLM-ready file
# ════════════════════════════════════════════════════════════════════════════
#  Homepage    https://github.com/CheginiSoroush/projdump
#  Docs        https://cheginisoroush.github.io/projdump/
#  Version     1.1.0
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
#  DESIGN RULES
#    * Zero hard dependencies beyond bash 5.0+, find and git.
#      Optional helpers (tree, jq, python3, file) are used when present
#      and silently skipped when not.
#    * A dump can never contain or corrupt itself: the output path is
#      always excluded, Markdown fences grow past any run of backticks
#      in the source, CDATA sections are split on "]]>" and XML
#      attributes are escaped.
#    * File pipelines are NUL-delimited, so filenames containing spaces,
#      tabs or literal newlines survive all three output formats.
#    * Runs 100% locally — no network access, no telemetry, ever.
#
#  EXIT CODES
#      0   success (also for --list, --version and --help)
#      1   error: bad usage, missing project directory, git failure,
#          unwritable output path, …
#
#  ENVIRONMENT
#      NO_COLOR    when set, diagnostics are printed without colour
#
#  FILES
#      lib/common.sh   shared helpers: colour palette, logging utilities
#      lib/lang.sh     language detection (120+ extensions) + binary check
#
#  EXAMPLES
#      projdump                                     # <project>_dump.md + clipboard
#      projdump -f xml -o review.xml                # XML for Claude
#      projdump --since HEAD~3 --list               # preview recent changes
#      projdump --tokens-budget 60000 --sort size-desc
#      projdump -e sh,py -x 'vendor/*' --note 'Find memory leaks'
#
#  SEE ALSO
#      README.md · docs/GOING-LIVE.md · test/functional.bats
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME="projdump"

# bash 5.2 enables `patsub_replacement` by default: a bare `&` in the
# replacement of ${var//pat/repl} expands to the matched text, which corrupts
# xml_escape() ("&quot; became '"quot;'). Turn it off globally; on older bash
# versions the option does not exist and this is a harmless no-op.
shopt -u patsub_replacement 2>/dev/null || true

# Resolve symlinks so lib/ is found when invoked via ~/.local/bin/projdump.
# Handled link-by-link (not `readlink -f`) so relative link targets resolve
# against the link's own directory rather than the caller's cwd.
SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$LINK_DIR/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"

# ─── Load libs ───────────────────────────────────────────────────────────────
# (if/then, not `&&`: a failing top-level && would abort the script under set -e)
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  # shellcheck source=lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/lang.sh" ]]; then
  # shellcheck source=lib/lang.sh
  source "$SCRIPT_DIR/lib/lang.sh"
fi

# ─── Fallbacks if libs are missing ───────────────────────────────────────────
command -v ok  >/dev/null 2>&1 || ok()  { printf '%s\n' "$*"; }
command -v inf >/dev/null 2>&1 || inf() { printf '%s\n' "$*"; }
command -v err >/dev/null 2>&1 || err() { printf '%s\n' "$*" >&2; }
command -v lang_for  >/dev/null 2>&1 || lang_for()  { printf 'text\n'; }
command -v is_binary >/dev/null 2>&1 || is_binary() {
  [[ -f "$1" ]] || return 1
  LC_ALL=C grep -qI . "$1" 2>/dev/null || return 0
  return 1
}

# ─── Optional tool availability (checked once) ───────────────────────────────
HAVE_TREE=0 HAVE_JQ=0 HAVE_PY3=0 HAVE_GIT=0
command -v tree    >/dev/null 2>&1 && HAVE_TREE=1
command -v jq      >/dev/null 2>&1 && HAVE_JQ=1
command -v python3 >/dev/null 2>&1 && HAVE_PY3=1
command -v git     >/dev/null 2>&1 && HAVE_GIT=1

# ─── Defaults ────────────────────────────────────────────────────────────────
OUT=""
SHOW_TREE=1
EXT_FILTER=""
MAX_FILE_SIZE=500      # KB
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

usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — Dump an entire project into one file for AI

Usage:
  ${SCRIPT_NAME} [output] [options]

Options:
  -o, --output FILE      Output file (default: <project>_dump.<ext>)
  -f, --format md|xml|json
                         Output format (default: md)
  -e, --ext-only sh,md   Only include files with these extensions
  -x, --exclude GLOB     Skip paths matching GLOB (repeatable)
  -i, --include GLOB     Only include paths matching GLOB (repeatable)
      --since REF        Only files changed since a git ref (needs git)
      --sort KEY         name | size | size-desc | ext   (default: name)
      --tokens-budget N  Stop adding files once ~N tokens are reached
      --max-size N       Skip files larger than N KB (default: ${MAX_FILE_SIZE})
      --no-tree          Don't include the directory tree
      --note TEXT        Add a "note for the AI" block at the top of the dump
      --list             Dry run: print what would be dumped and exit
      --stdout           Write the dump to stdout instead of a file
      --copy | --no-copy Force / disable clipboard copy (default: auto)
  -v, --verbose          Explain skipped files on stderr
  -q, --quiet            Don't print the summary
      --version          Show version
  -h, --help             Show this help

Examples:
  ${SCRIPT_NAME}                          # <project>_dump.md in the cwd
  ${SCRIPT_NAME} -o out.md                # custom output name
  ${SCRIPT_NAME} -e sh,bats               # only shell files
  ${SCRIPT_NAME} -x 'test/*' -x '*.min.js'  # skip paths (repeatable)
  ${SCRIPT_NAME} -i 'src/*' -i 'docs/*'   # only these paths
  ${SCRIPT_NAME} --since HEAD~5           # only what changed lately
  ${SCRIPT_NAME} --tokens-budget 60000    # fit a context window
  ${SCRIPT_NAME} --sort size-desc         # biggest files first
  ${SCRIPT_NAME} --list                   # preview the file list
  ${SCRIPT_NAME} --note 'Review auth for security bugs'
  ${SCRIPT_NAME} --format xml             # XML (Claude-friendly)
  ${SCRIPT_NAME} --stdout | pbcopy        # pipe straight to the clipboard
EOF
}

die() { err "$SCRIPT_NAME: $*"; exit 1; }

require_value() {
  [[ $# -ge 2 && -n "${2:-}" ]] || die "option '$1' requires a value"
}

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-tree)   SHOW_TREE=0; shift ;;
    --ext-only|-e)     require_value "$@"; EXT_FILTER="$2"; shift 2 ;;
    --exclude|-x)      require_value "$@"; EXCLUDES+=("$2"); shift 2 ;;
    --include|-i)      require_value "$@"; INCLUDES+=("$2"); shift 2 ;;
    --max-size)  require_value "$@"; MAX_FILE_SIZE="$2"; shift 2 ;;
    --format|-f) require_value "$@"; FORMAT="$2"; shift 2 ;;
    --output|-o) require_value "$@"; OUT="$2"; shift 2 ;;
    --since)     require_value "$@"; SINCE="$2"; shift 2 ;;
    --sort)      require_value "$@"; SORT_KEY="$2"; shift 2 ;;
    --tokens-budget) require_value "$@"; BUDGET="$2"; shift 2 ;;
    --note)      require_value "$@"; NOTE="$2"; shift 2 ;;
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

case "$FORMAT" in md|xml|json) ;; *) die "Unknown format: '$FORMAT' (use md, xml or json)" ;; esac
[[ "$MAX_FILE_SIZE" =~ ^[0-9]+$ ]] || die "--max-size expects a number, got '$MAX_FILE_SIZE'"
[[ "$BUDGET" =~ ^[0-9]+$ ]] || die "--tokens-budget expects a number, got '$BUDGET'"
case "$SORT_KEY" in name|size|size-desc|ext) ;; *) die "Unknown sort key: '$SORT_KEY' (use name, size, size-desc or ext)" ;; esac

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
  # FIX (1.1.0): reject directory targets instead of `mv` silently moving
  # the dump *inside* them.
  [[ "$OUT" == */ ]] && die "output path '$OUT' ends with '/' — give a file path"
  if [[ -d "$OUT" ]]; then
    die "output path '$OUT' is an existing directory — give a file path"
  fi
  out_dir="$(dirname -- "$OUT")"
  if [[ ! -d "$out_dir" ]]; then
    mkdir -p -- "$out_dir" 2>/dev/null || die "cannot create output directory '$out_dir'"
    (( VERBOSE )) && inf "created output directory: $out_dir"
  fi
  # FIX (1.1.0): compare the full relative path (was: basename only), so a
  # dump written to a subdirectory can never include itself on the next run.
  OUT_REL="${OUT#./}"
fi

# ─── Small helpers ───────────────────────────────────────────────────────────
xml_escape() {
  local s="$1"
  # Self-contained guard: the function must behave identically even when
  # extracted/sourced into a shell where patsub_replacement is still on.
  shopt -u patsub_replacement 2>/dev/null || true
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# JSON string encoder: jq → python3 → awk fallback
# NOTE: pipe with printf, never a here-string — `<<<` appends a newline, which
# would silently add "\n" to every JSON scalar.
json_escape() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))'
  else
    {
      printf '"'
      printf '%s' "$1" | awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,"\\r");
        if (NR>1) printf "\\n";
        printf "%s", $0
      }'
      printf '"\n'
    }
  fi
}

# FIX (1.1.0): file contents used to be passed through "$(cat file)", which
# strips *every* trailing newline — dumps lost them. Feeding the file via
# stdin keeps the bytes exactly as they are (jq/python3 paths).
json_escape_file() {
  local f="$1" fsz
  if (( HAVE_JQ )); then
    jq -Rs . <"$f"
  elif (( HAVE_PY3 )); then
    python3 -c 'import sys, json; sys.stdout.write(json.dumps(sys.stdin.read()) + "\n")' <"$f"
  else
    # Pure-awk fallback. awk consumes one newline per record; reconstruct the
    # trailing newline(s) by comparing the file size (bytes, LC_ALL=C) with
    # the record lengths, so "a\n" encodes as "a\n" and not "a".
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

human_size() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$b" 2>/dev/null && return 0
  fi
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB", u, " ");
    i = 1;
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d%s" : "%.1f%s"), b, u[i]
  }'
}

# FIX (1.1.0): `wc -l` undercounts files without a trailing newline.
# `grep -c ''` counts every line including an unterminated last line.
line_count() {
  local n
  n="$(LC_ALL=C grep -c '' -- "$1" 2>/dev/null)" || n=0
  printf '%s' "$n"
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

# ─── Collect candidate files ─────────────────────────────────────────────────
# git repos: tracked + untracked-but-not-ignored files. Otherwise: find.
# The dump itself is always excluded, so a dump can never contain itself.
collect_files() {
  if (( HAVE_GIT )) && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$SINCE" ]]; then
      # Files that changed since $SINCE (added/copied/modified/renamed,
      # compared against the working tree) plus untracked files.
      {
        git diff --name-only -z --diff-filter=ACMR "$SINCE" 2>/dev/null || true
        git ls-files -z -o --exclude-standard 2>/dev/null || true
      } | sort -zu
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

F_SIZE=0  # last measured size (bytes), set by should_include, reused by measure

should_include() {
  local f="$1" rel="${1#./}" base ext size_bytes a
  local -a allowed=()
  [[ -f "$f" ]] || { skip "$rel" "not a regular file"; return 1; }

  # never dump the dump
  [[ -n "$OUT_REL" && "$rel" == "$OUT_REL" ]] && { skip "$rel" "output file"; return 1; }

  if (( ${#EXCLUDES[@]} )); then
    excluded "$f" && { skip "$rel" "excluded"; return 1; }
  fi

  if (( ${#INCLUDES[@]} )) && ! included "$f"; then
    skip "$rel" "not included"
    return 1
  fi

  if [[ -n "$EXT_FILTER" ]]; then
    # FIX (1.1.0): the extension must come from the *basename*, so paths like
    # "my.dir/file" (no extension) are no longer misread as ext="dir/file".
    base="${rel##*/}"
    [[ "$base" == *.* ]] || { skip "$rel" "no extension"; return 1; }
    ext="${base##*.}"
    local match=0
    IFS=',' read -ra allowed <<<"$EXT_FILTER"
    for a in "${allowed[@]}"; do
      a="${a//[[:space:]]/}"     # tolerate "sh, md"
      a="${a#.}"
      if [[ -n "$a" && "${ext,,}" == "${a,,}" ]]; then match=1; break; fi
    done
    if (( ! match )); then skip "$rel" "extension filter"; return 1; fi
  fi

  # FIX (1.1.0): compare raw bytes (was: floored KB), so a 1536-byte file no
  # longer slips through `--max-size 1`.
  size_bytes="$(file_size_bytes "$f")"
  if (( size_bytes > MAX_FILE_SIZE * 1024 )); then
    skip "$rel" "too large"
    return 1
  fi
  F_SIZE="$size_bytes"

  if is_binary "$f"; then
    skip "$rel" "binary"
    return 1
  fi
  return 0
}

# ─── Measure once, reuse everywhere ──────────────────────────────────────────
declare -A SIZES=() LINES=() LANG_OF=()
declare -A L_FILES=() L_LINES=() L_BYTES=()
declare -a FILES=() LANG_ORDER=()
STAT_FILES=0 STAT_LINES=0 STAT_BYTES=0 STAT_TOKENS=0

measure_file() {
  local rel="${1#./}"
  SIZES["$rel"]="$F_SIZE"
  LINES["$rel"]="$(line_count "$1")"
}

compute_totals() {
  local f rel
  STAT_FILES=${#FILES[@]}
  STAT_LINES=0
  STAT_BYTES=0
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    STAT_LINES=$(( STAT_LINES + ${LINES["$rel"]:-0} ))
    STAT_BYTES=$(( STAT_BYTES + ${SIZES["$rel"]:-0} ))
  done
  STAT_TOKENS=$(( STAT_BYTES * 10 / 35 ))
  return 0
}

compute_lang_stats() {
  local f rel lang
  LANG_ORDER=()
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    lang="$(lang_for "$f")"
    LANG_OF["$rel"]="$lang"
    L_FILES["$lang"]=$(( ${L_FILES["$lang"]:-0} + 1 ))
    L_LINES["$lang"]=$(( ${L_LINES["$lang"]:-0} + ${LINES["$rel"]:-0} ))
    L_BYTES["$lang"]=$(( ${L_BYTES["$lang"]:-0} + ${SIZES["$rel"]:-0} ))
  done
  # order languages by bytes (desc) so the table is stable and meaningful
  local l
  while IFS=$'\t' read -r _ l; do
    LANG_ORDER+=("$l")
  done < <(
    for l in "${!L_FILES[@]}"; do
      printf '%012d\t%s\n' "${L_BYTES["$l"]:-0}" "$l"
    done | LC_ALL=C sort -r
  )
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
        size|size-desc) key="$(printf '%012d' "${SIZES["$rel"]:-0}")" ;;
        ext)
          ext="${rel##*/}"
          if [[ "$ext" == *.* ]]; then ext="${ext##*.}"; else ext=""; fi
          key="${ext,,}"
          ;;
        *) key="" ;;
      esac
      printf '%s\t%s\0' "$key" "$rel"
    done < <(printf '%s\0' "${FILES[@]}") | sort -z "${sflags[@]}"
  )
  FILES=("${ordered[@]}")
  return 0
}

apply_budget() {
  (( BUDGET > 0 )) || return 0
  local -a keep=()
  local f rel t total=0 n=0
  for f in "${FILES[@]}"; do
    rel="${f#./}"
    t=$(( ${SIZES["$rel"]:-0} * 10 / 35 ))
    if (( n > 0 && total + t > BUDGET )); then
      skip "$rel" "over token budget"
      continue
    fi
    total=$(( total + t ))
    n=$(( n + 1 ))
    keep+=("$f")
  done
  FILES=("${keep[@]}")
  return 0
}

prepare_files() {
  local f
  while IFS= read -r -d '' f; do
    if should_include "$f"; then
      measure_file "$f"
      FILES+=("$f")
    fi
  done < <(collect_files)
  apply_sort
  apply_budget
  compute_lang_stats
  compute_totals
  return 0
}

# ─── Writers ─────────────────────────────────────────────────────────────────
# A fence longer than any backtick run inside the file, so nested ``` cannot
# break the Markdown block.
fence_for() {
  local f="$1" longest=0 run fence="" need
  while IFS= read -r run; do
    if (( ${#run} > longest )); then longest=${#run}; fi
  done < <(LC_ALL=C grep -o '`\{3,\}' "$f" 2>/dev/null || true)
  need=$(( longest + 1 ))
  if (( need < 3 )); then need=3; fi
  while (( ${#fence} < need )); do fence+='`'; done
  printf '%s' "$fence"
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

# The tree is built from the files that actually made it into the dump, so it
# works with or without tree(1) and never lists junk directories.
write_tree_md() {
  if [[ "$SHOW_TREE" != "1" ]]; then return 0; fi
  local -a list=()
  local f tree_out=""
  for f in "$@"; do list+=("${f#./}"); done

  echo "## 📁 Directory Tree"
  echo
  echo '```'
  if (( ${#list[@]} )) && (( HAVE_TREE )); then
    tree_out="$(printf '%s\n' "${list[@]}" | tree --fromfile --noreport . 2>/dev/null || true)"
  fi
  if [[ -n "$tree_out" ]]; then
    printf '%s\n' "$tree_out"
  elif (( ${#list[@]} )); then
    printf '%s\n' "${list[@]}" | sort -u
  else
    echo "(no files)"
  fi
  echo '```'
  echo
  echo "---"
  echo
}

write_file_md() {
  local f="$1" rel="${1#./}" fence
  fence="$(fence_for "$f")"
  echo "### \`$rel\`"
  echo
  echo "${fence}$(lang_for "$f")"
  cat -- "$f"
  # only pad when the file has no trailing newline, so we don't invent a blank line
  if [[ -s "$f" && -n "$(tail -c1 -- "$f")" ]]; then echo; fi
  echo "$fence"
  echo
  echo "<sub>${LINES["$rel"]:-0} lines · $(human_size "${SIZES["$rel"]:-0}")</sub>"
  echo
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
  echo "> Roughly ${STAT_TOKENS} tokens (bytes ÷ 3.5)"

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
      done | LC_ALL=C sort -z -k1,1r
    )
    for rel in "${top[@]}"; do
      # shellcheck disable=SC2016  # backticks are literal Markdown in the format
      printf -- '- `%s` — %s lines · %s\n' \
        "$rel" "${LINES["$rel"]:-0}" "$(human_size "${SIZES["$rel"]:-0}")"
    done
  fi
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
  local f rel l git_info

  case "$FORMAT" in
    md)
      write_header_md
      write_tree_md "${FILES[@]}"
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
      printf '<project name="%s" path="%s" generated="%s" tool="%s"' \
        "$(xml_escape "$PROJECT_NAME")" "$(xml_escape "$PWD")" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(xml_escape "$SCRIPT_NAME v$SCRIPT_VERSION")"
      if git_info="$(git_summary)"; then
        printf ' git="%s"' "$(xml_escape "$git_info")"
      fi
      if [[ -n "$SINCE" ]]; then
        printf ' since="%s"' "$(xml_escape "$SINCE")"
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
        printf '  <file path="%s" lang="%s" lines="%s" bytes="%s">\n' \
          "$(xml_escape "$rel")" "$(xml_escape "${LANG_OF["$rel"]:-text}")" \
          "${LINES["$rel"]:-0}" "${SIZES["$rel"]:-0}"
        echo "    <![CDATA["
        # A literal ]]> inside the file would close the CDATA section early,
        # so split it: "]]" + "><![CDATA[" + ">"
        if LC_ALL=C grep -q ']]>' "$f" 2>/dev/null; then
          sed 's/]]>/]]]]><![CDATA[>/g' -- "$f"
        else
          cat -- "$f"
        fi
        echo
        echo "    ]]>"
        echo "  </file>"
      done
      printf '  <stats files="%s" lines="%s" bytes="%s" tokens="%s">\n' \
        "$STAT_FILES" "$STAT_LINES" "$STAT_BYTES" "$STAT_TOKENS"
      for l in "${LANG_ORDER[@]}"; do
        printf '    <language name="%s" files="%s" lines="%s" bytes="%s"/>\n' \
          "$(xml_escape "$l")" "${L_FILES["$l"]:-0}" "${L_LINES["$l"]:-0}" "${L_BYTES["$l"]:-0}"
      done
      echo '  </stats>'
      echo "</project>"
      ;;
    json)
      printf '{\n'
      printf '  "project": %s,\n'    "$(json_escape "$PROJECT_NAME")"
      printf '  "path": %s,\n'       "$(json_escape "$PWD")"
      printf '  "generated": %s,\n'  "$(json_escape "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
      printf '  "tool": %s,\n'       "$(json_escape "$SCRIPT_NAME v$SCRIPT_VERSION")"
      if git_info="$(git_summary)"; then
        printf '  "git": %s,\n' "$(json_escape "$git_info")"
      fi
      if [[ -n "$SINCE" ]]; then
        printf '  "since": %s,\n' "$(json_escape "$SINCE")"
      fi
      if [[ -n "$NOTE" ]]; then
        printf '  "note": %s,\n' "$(json_escape "$NOTE")"
      fi
      printf '  "files": ['
      local first=1
      for f in "${FILES[@]}"; do
        rel="${f#./}"
        (( first )) || printf ',\n'
        first=0
        printf '\n    {"path": %s, "lang": %s, "lines": %s, "bytes": %s, "content": %s}' \
          "$(json_escape "$rel")" \
          "$(json_escape "${LANG_OF["$rel"]:-text}")" \
          "${LINES["$rel"]:-0}" \
          "${SIZES["$rel"]:-0}" \
          "$(json_escape_file "$f")"
      done
      printf '\n  ],\n'
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

# ─── Run ─────────────────────────────────────────────────────────────────────
TMP_OUT=""
cleanup() {
  [[ -n "$TMP_OUT" ]] && rm -f -- "$TMP_OUT"
  # bash uses the EXIT trap's last status as the script's exit status —
  # without this, a successful run would exit 1 whenever TMP_OUT was empty.
  return 0
}
trap cleanup EXIT

prepare_files

if (( VERBOSE )); then
  inf "→ ${STAT_FILES} files selected · ~${STAT_TOKENS} tokens"
fi

if (( LIST_ONLY )); then
  run_list
  exit 0
fi

if (( VERBOSE )) && (( SKIPPED_TOTAL > 0 )); then
  inf "→ ${SKIPPED_TOTAL} files skipped (see above)"
fi

TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/projdump.out.XXXXXX")"
run_dump >"$TMP_OUT"

if [[ "$STDOUT" -eq 1 ]]; then
  cat -- "$TMP_OUT"
else
  mv -- "$TMP_OUT" "$OUT"
  TMP_OUT=""
fi

# ─── Report ──────────────────────────────────────────────────────────────────
if (( ! QUIET )); then
  ok "✓ ${STAT_FILES} files · ${STAT_LINES} lines · $(human_size "$STAT_BYTES") · ~${STAT_TOKENS} tokens"
  if (( ! STDOUT )); then
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
    putclip <"$src"                        # Cygwin
  elif command -v xclip >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xclip -selection clipboard <"$src"
  elif command -v xsel >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xsel --clipboard --input <"$src"
  else
    return 1
  fi
}

if [[ "$COPY_MODE" != "no" && "$STDOUT" -eq 0 ]]; then
  copy_to_clipboard "$OUT" 2>/dev/null && ok "✓ Copied to clipboard" || true
fi
