#!/usr/bin/env bats
# File selection: ext / exclude / include / size / budget / sort / since / gitignore.
load helpers

setup() {
  new_repo
  a alpha.sh   'echo a'
  a beta.py    'x = 1'
  a gamma.md   '# doc'
  a big.js     'y'
  a sub/delta.sh 'echo d'
}

@test "ext: -e keeps only the given extensions" {
  run_pd --no-tree -e sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.sh"* ]] && [[ "$output" == *"delta.sh"* ]]
  [[ "$output" != *"beta.py"* ]] && [[ "$output" != *"gamma.md"* ]]
}

@test "ext: -e is case-insensitive" {
  a Upper.SH 'echo up'
  run_pd --no-tree -e sh --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upper.SH"* ]]
}

@test "ext: -e takes a comma-separated list" {
  run_pd --no-tree -e sh,md
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.sh"* ]] && [[ "$output" == *"gamma.md"* ]]
  [[ "$output" != *"beta.py"* ]]
}

@test "exclude: -x drops matching paths" {
  run_pd --no-tree -x 'sub/*'
  [ "$status" -eq 0 ]
  [[ "$output" != *"delta.sh"* ]]
  [[ "$output" == *"alpha.sh"* ]]
}

@test "exclude: -x repeats and supports globs" {
  run_pd --no-tree -x '*.sh' -x '*.py'
  [ "$status" -eq 0 ]
  [[ "$output" != *"alpha.sh"* ]] && [[ "$output" != *"beta.py"* ]]
  [[ "$output" == *"gamma.md"* ]]
}

@test "include: -i keeps only matching paths" {
  run_pd --no-tree -i 'sub/*'
  [ "$status" -eq 0 ]
  [[ "$output" == *"delta.sh"* ]]
  [[ "$output" != *"alpha.sh"* ]] && [[ "$output" != *"beta.py"* ]]
}

@test "include: several -i flags union" {
  run_pd --no-tree -i '*.py' -i '*.md'
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta.py"* ]] && [[ "$output" == *"gamma.md"* ]]
  [[ "$output" != *"alpha.sh"* ]]
}

@test "size: --max-size skips files over the limit" {
  head -c 3000 /dev/zero | tr '\0' 'x' > huge.txt
  run_pd --no-tree --max-size 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"huge.txt"* ]]
  [[ "$output" == *"alpha.sh"* ]]
}

@test "size: --max-size 0 disables the limit" {
  head -c 3000 /dev/zero | tr '\0' 'x' > huge.txt
  run_pd --no-tree --max-size 0 -e txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"huge.txt"* ]]
}

@test "size: a file exactly at the limit is kept" {
  head -c 1024 /dev/zero | tr '\0' 'x' > exact.txt
  run_pd --no-tree --max-size 1 -e txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"exact.txt"* ]]
}

@test "budget: --tokens-budget keeps the first file always" {
  run_pd --no-tree --tokens-budget 1
  [ "$status" -eq 0 ]
  # alpha.sh sorts first and must survive even with a tiny budget
  [[ "$output" == *"alpha.sh"* ]]
  [[ "$output" != *"beta.py"* ]]
}

@test "budget: verbose explains the over-budget skips" {
  run bash "$PD" --quiet --no-copy --no-config --stdout --no-tree --tokens-budget 1 --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"over token budget"* ]]
}

@test "sort: --sort size-desc puts the biggest file first" {
  head -c 5000 /dev/zero | tr '\0' 'x' > large.txt
  run bash "$PD" --quiet --no-copy --no-config --stdout --no-tree --sort size-desc --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
paths = [f["path"] for f in json.loads(sys.argv[1])["files"]]
assert paths[0] == "large.txt", paths
print("ok")
PY
}

@test "sort: --sort ext groups by extension" {
  run bash "$PD" --quiet --no-copy --no-config --stdout --no-tree --sort ext --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
paths = [f["path"] for f in json.loads(sys.argv[1])["files"]]
exts = [p.rsplit(".", 1)[-1] for p in paths]
assert exts == sorted(exts), paths
print("ok")
PY
}

@test "since: --since dumps only newer files plus untracked" {
  a newer.txt 'fresh'
  run_pd --no-tree --since HEAD~1
  [ "$status" -eq 0 ]
  [[ "$output" == *"newer.txt"* ]]
  [[ "$output" != *"alpha.sh"* ]]
  printf 'untracked' > stray.txt
  run_pd --no-tree --since HEAD~1 -e txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"stray.txt"* ]]
}

@test "gitignore: gitignored files are skipped inside repos" {
  printf 'ignored.txt\n' > .gitignore
  printf 'x' > ignored.txt
  run_pd --no-tree
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2016  # markdown header pattern contains literal backticks
  [[ "$output" != *'### `ignored.txt`'* ]]
}

@test "binary: known binary extensions are skipped" {
  printf 'not really a png' > photo.PNG
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" != *"photo.PNG"* ]]
}

@test "binary: NUL bytes mark unknown extensions as binary" {
  printf 'text\0with-nul' > blob.xyzbin
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" != *"blob.xyzbin"* ]]
}

@test "verbose: skipped files come with a reason" {
  printf 'x' > image.jpg
  run bash "$PD" --quiet --no-copy --no-config --stdout --no-tree --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"image.jpg"* ]]
  [[ "$output" == *"binary"* ]]
}

@test "empty: a project with no text files reports it cleanly" {
  rm -f alpha.sh beta.py gamma.md big.js sub/delta.sh
  rm -rf .git
  run_pd
  [ "$status" -eq 0 ]
  [[ "$output" == *"_No files matched._"* ]]
}
