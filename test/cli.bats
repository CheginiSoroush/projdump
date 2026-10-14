#!/usr/bin/env bats
# CLI surface: version, help, validation, list mode, config, models, split.
load helpers

setup() { new_repo; }

@test "version: --version prints v2.0.2" {
  run bash "$PD" --version
  [ "$status" -eq 0 ]
  [ "$output" = "projdump v2.0.2" ]
}

@test "version: -h and --help print usage and exit 0" {
  run bash "$PD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run bash "$PD" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"projdump [output] [options]"* ]]
}

@test "cli: unknown option is rejected" {
  run bash "$PD" --bogus-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "cli: --format rejects an unknown format" {
  run bash "$PD" --format pdf --stdout
  [ "$status" -ne 0 ]
  [[ "$output" == *"pdf"* ]]
}

@test "cli: --sort rejects an unknown key" {
  run bash "$PD" --sort sideways --stdout
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown sort key"* ]]
}

@test "cli: --model rejects an unknown model" {
  run bash "$PD" --model hal-9000 --stdout
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown model"* ]]
}

@test "models: --list-models lists every preset" {
  run bash "$PD" --list-models
  [ "$status" -eq 0 ]
  for m in gpt-4o gpt-4.1 o3 claude-sonnet claude-opus gemini-2.5-pro deepseek-v3 llama-3.1; do
    [[ "$output" == *"$m"* ]]
  done
}

@test "models: --model sets the matching token budget" {
  head -c 450000 /dev/zero | tr '\0' 'a' > zzz.py   # ~128k code tokens > gpt-4o budget, under max-size
  a aaa.py 'print("hi")'                            # sorts first — always kept
  run_pd --model gpt-4o --no-tree --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip: zzz.py (over token budget)"* ]]
  [[ "$output" == *"aaa.py"* ]]      # first file is never dropped
}

@test "cli: default output is <stem>_dump.md" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --no-config
  [ "$status" -eq 0 ]
  [ -f "$REPO/${REPO##*/}_dump.md" ]
}

@test "cli: -o renames the output file" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --no-config -o custom.md
  [ "$status" -eq 0 ]
  [ -f "$REPO/custom.md" ]
}

@test "cli: --format xml/json pick the extension" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --no-config --format xml
  [ "$status" -eq 0 ]
  [ -f "$REPO/${REPO##*/}_dump.xml" ]
  run bash "$PD" --quiet --no-copy --no-config --format json
  [ "$status" -eq 0 ]
  [ -f "$REPO/${REPO##*/}_dump.json" ]
}

@test "cli: the dump never contains itself" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --no-config
  [ "$status" -eq 0 ]
  local out="$REPO/${REPO##*/}_dump.md"
  [ -f "$out" ]
  run bash "$PD" --quiet --no-copy --no-config
  [ "$status" -eq 0 ]
  [ ! -e "$REPO/${REPO##*/}_dump_dump.md" ]
  run grep -q "dump.md" "$out"
  [ "$status" -ne 0 ]
}

@test "list: --list is a dry run and writes no file" {
  a one.txt 'x'
  a src/two.py 'y'
  run bash "$PD" --list --no-copy --no-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"one.txt"* ]] && [[ "$output" == *"two.py"* ]]
  [ ! -e "$REPO/${REPO##*/}_dump.md" ]
}

@test "list: --list --sort size-desc shows the biggest first" {
  a big.txt   'aaaaaaaaaa'
  a small.txt 'a'
  run bash "$PD" --list --no-copy --no-config --sort size-desc
  [ "$status" -eq 0 ]
  [[ "$output" == *"big.txt"*"small.txt"* ]]
}

@test "cli: --quiet suppresses the summary line" {
  a one.txt 'x'
  run bash "$PD" --no-copy --no-config --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"files ·"*"lines"* ]]     # the ✓ summary line
  run_pd
  [ "$status" -eq 0 ]
  [[ "$output" != *"files ·"* ]]            # summary gone, dump only
}

@test "cli: --note lands at the top of the dump" {
  a one.txt 'x'
  run_pd --note 'Focus on the login flow'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Focus on the login flow"* ]]
  [[ "${output%%Source Files*}" == *"Focus on the login flow"* ]]
}

@test "config: XDG config is auto-loaded" {
  a one.txt 'x'
  mkdir -p xdg/projdump
  printf 'NOTE="from the xdg config"\n' > xdg/projdump/config
  XDG_CONFIG_HOME="$REPO/xdg" run bash "$PD" --quiet --no-copy --stdout -x 'xdg/*'
  [ "$status" -eq 0 ]
  [[ "$output" == *"from the xdg config"* ]]
}

@test "config: project-local .projdumprc is never auto-sourced" {
  a one.txt 'x'
  printf 'echo pwned > pwned-canary.txt\nNOTE="from the repo rc"\n' > .projdumprc
  run bash "$PD" --quiet --no-copy --stdout -x '.projdumprc'
  [ "$status" -eq 0 ]
  [[ "$output" != *"from the repo rc"* ]]
  [ ! -e "$REPO/pwned-canary.txt" ]
  [[ "$output" == *"--config .projdumprc"* ]]   # migration notice points at the new form
}

@test "config: --no-config silences the notice and ignores the repo rc" {
  a one.txt 'x'
  printf 'NOTE="from the repo rc"\nFORMAT="xml"\n' > .projdumprc
  run bash "$PD" --quiet --no-copy --stdout --no-config -x '.projdumprc'
  [ "$status" -eq 0 ]
  [[ "$output" != *"from the repo rc"* ]]
  [[ "$output" != *"no longer auto-loaded"* ]]
  [[ "$output" != *"<project"* ]]               # FORMAT=xml from the rc was not applied
}

@test "config: --config .projdumprc loads it explicitly" {
  a one.txt 'x'
  printf 'NOTE="explicit project config"\n' > .projdumprc
  run bash "$PD" --quiet --no-copy --stdout --config .projdumprc -x '.projdumprc'
  [ "$status" -eq 0 ]
  [[ "$output" == *"explicit project config"* ]]
}

@test "config: --config without a value fails with a clear error" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --stdout --config
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "config: --config FILE wins over the repo rc" {
  a one.txt 'x'
  printf 'NOTE="repo rc"\n' > .projdumprc
  printf 'NOTE="explicit file"\n' > other.rc
  run bash "$PD" --quiet --no-copy --stdout --config other.rc -x '.projdumprc' -x 'other.rc'
  [ "$status" -eq 0 ]
  [[ "$output" == *"explicit file"* ]]
  [[ "$output" != *"repo rc"* ]]
}

@test "split: --split writes part files under the budget" {
  a f1.md "$(head -c 200 /dev/zero | tr '\0' 'a')"
  a f2.md "$(head -c 200 /dev/zero | tr '\0' 'a')"
  a f3.md "$(head -c 200 /dev/zero | tr '\0' 'a')"
  run bash "$PD" --quiet --no-copy --no-config --split 60
  [ "$status" -eq 0 ]
  local stem="${REPO##*/}_dump"
  local parts=("$REPO/$stem".part*.md)
  [ "${#parts[@]}" -ge 2 ]
  [ ! -e "$REPO/$stem.md" ]
}

@test "split: --split is rejected together with --stdout" {
  a one.txt 'x'
  run_pd --split 100
  [ "$status" -ne 0 ]
  [[ "$output" == *"--split requires writing files"* ]]
}

@test "split: invalid --split values are rejected" {
  a one.txt 'x'
  run bash "$PD" --quiet --no-copy --no-config --split bananas
  [ "$status" -ne 0 ]
  [[ "$output" == *"split"* ]]
}
