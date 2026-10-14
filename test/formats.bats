#!/usr/bin/env bats
# Output formats: markdown, XML and JSON shapes.
load helpers

setup() { new_repo; a src/main.py $'print("hello")\n'; }

@test "md: header block with project name and tool version" {
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project Dump"* ]]
  [[ "$output" == *"projdump v2.0.2"* ]]
}

@test "md: directory tree section" {
  run_pd
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 📁 Directory Tree"* ]]
  [[ "$output" == *"main.py"* ]]
}

@test "md: fenced code block with the language tag" {
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *'```python'* ]]
  [[ "$output" == *"print(\"hello\")"* ]]
}

@test "md: per-file footer with lines and size" {
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"<sub>1 lines · 15B</sub>"* ]]
}

@test "md: summary table and language breakdown" {
  run_pd --no-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 📊 Summary"* ]]
  [[ "$output" == *"### 🗂️ Languages"* ]]
  [[ "$output" == *"python"* ]]
}

@test "md: --tree-depth limits the tree" {
  a deep/a/b/c/leaf.txt 'x'
  run_pd --tree-depth 1
  [ "$status" -eq 0 ]
  local tree="${output##*Directory Tree}"
  tree="${tree%%Source Files*}"
  [[ "$tree" == *"…"* ]]
  [[ "$tree" != *"leaf.txt"* ]]
  run_pd
  local full="${output##*Directory Tree}"
  full="${full%%Source Files*}"
  [[ "$full" == *"leaf.txt"* ]]
}

@test "xml: root project element with tool attribute" {
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *'<project name="repo'* ]]
  [[ "$output" == *'tool="projdump v2.0.2"'* ]]
}

@test "xml: file element with path, lang and CDATA content" {
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *'<file path="src/main.py" lang="python" lines="1" bytes="15">'* ]]
  [[ "$output" == *"<![CDATA["* ]]
  [[ "$output" == *"print(\"hello\")"* ]]
}

@test "xml: stats element with file count and tokens" {
  run_pd --no-tree --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *'<stats files="1" lines="1" bytes="15" tokens="5">'* ]]
}

@test "json: valid JSON, exact content, byte-identical newline" {
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["project"].startswith("repo"), d["project"]
f = d["files"][0]
assert f["path"] == "src/main.py"
assert f["content"] == 'print("hello")\n', repr(f["content"])
assert d["stats"]["files"] == 1
assert d["stats"]["languages"]["python"]["lines"] == 1
print("ok")
PY
}

@test "json: files keep sorted-by-name order" {
  a zz.py 'x'
  a aa.py 'y'
  run_pd --no-tree --format json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
paths = [f["path"] for f in json.loads(sys.argv[1])["files"]]
assert paths == sorted(paths), paths
print("ok")
PY
}

@test "md: fences grow past runs of backticks" {
  printf 'a `` b\n' > ticks.md
  printf '```\n' > fence3.md
  run_pd --no-tree -e md
  [ "$status" -eq 0 ]
  [[ "$output" == *"````"* ]]
}

@test "xml: CDATA end-marker inside content is split safely" {
  printf 'x ]]> y\n' > cdata.txt
  run_pd --no-tree --format xml -e txt
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import sys
doc = sys.argv[1]
assert 'path="cdata.txt"' in doc
assert "]]]]><![CDATA[>" in doc, "split marker missing"
assert "x ]]> y" not in doc, "raw ]]> leaked"
joined = doc.replace("]]]]><![CDATA[>", "]]>")
assert "x ]]> y" in joined, "round-trip broken"
print("ok")
PY
}
