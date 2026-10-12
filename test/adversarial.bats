#!/usr/bin/env bats
# Adversarial cases: hostile filenames, edge content, git extras.
load helpers

setup() { new_repo; }

@test "names: spaces in filenames survive all three formats" {
  a 'folder with spaces/file one.txt' 'x'
  run_pd --no-tree --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *"file one.txt"* ]]
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *"folder with spaces/file one.txt"* ]]
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["files"][0]["path"] == "folder with spaces/file one.txt"
print("ok")
PY
}

@test "names: newlines in filenames survive the pipeline" {
  a $'weird\nname.txt' 'x'
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert "weird\nname.txt" in [f["path"] for f in d["files"]]
print("ok")
PY
}

@test "names: double quotes in filenames are escaped in XML" {
  a 'file "quoted".txt' 'x'
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *'file &quot;quoted&quot;.txt'* ]]
}

@test "names: angle brackets and ampersands are escaped in XML" {
  a 'a<b&c>.txt' 'x'
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *'a&lt;b&amp;c&gt;.txt'* ]]
}

@test "content: missing trailing newline is preserved exactly in JSON" {
  printf 'no newline at end' > raw.txt
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["files"][0]["content"] == "no newline at end"
print("ok")
PY
}

@test "content: missing trailing newline gets padded in Markdown" {
  printf 'no newline at end' > raw.txt
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"no newline at end"$'\n'* ]]
}

@test "content: empty files are included with 0 lines and 0B" {
  : > empty.txt
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty.txt"* ]]
  [[ "$output" == *"0 lines · 0B"* ]]
}

@test "content: SVG files are treated as text" {
  a icon.svg '<svg xmlns="http://www.w3.org/2000/svg"/>'
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"icon.svg"* ]]
  [[ "$output" == *"svg xmlns="* ]]
}

@test "tokens: weighting differs per language class" {
  head -c 100 /dev/zero | tr '\0' 'a' > same.md     # prose -> ceil(1000/40) = 25
  head -c 100 /dev/zero | tr '\0' 'a' > same.json   # data  -> ceil(1000/32) = 32
  run bash "$PD" --list --no-copy --no-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"~57 tokens"* ]]
  rm same.md
  run bash "$PD" --list --no-copy --no-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"~32 tokens"* ]]
}

@test "git: header carries the branch and commit" {
  a one.txt 'x'
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Git:**"*"@"* ]]
}

@test "git: --git-log appends the recent-commits section" {
  a one.txt 'first'
  a two.txt 'second'
  run_pd --no-tree --git-log 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent commits"* ]]
  [[ "$output" == *"add two.txt"* ]]
}

@test "names: leading-dot files are included" {
  a .env 'SECRET=1'
  a .editorconfig 'root = true'
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *".env"* ]]
  [[ "$output" == *".editorconfig"* ]]
}

@test "names: unicode filenames survive" {
  a 'مخزن/فایل-فارسی.txt' 'سلام'
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert "مخزن/فایل-فارسی.txt" in [f["path"] for f in d["files"]]
print("ok")
PY
}
