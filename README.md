<div align="center">

<img src="docs/assets/banner.svg" alt="projdump — dump your whole project into one file for AI" width="100%">

# 📦 projdump

**Your whole codebase. One file. AI-ready.**

Dump an entire project — tree, sources and stats — into a single Markdown, XML or JSON file,
ready to paste into **Claude**, **ChatGPT**, **DeepSeek**, **Gemini** or any LLM.

[![CI](https://github.com/CheginiSoroush/projdump/actions/workflows/ci.yml/badge.svg)](https://github.com/CheginiSoroush/projdump/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![bash](https://img.shields.io/badge/bash-5.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![tests](https://img.shields.io/badge/tests-68%20passing-2EA043)](test/)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-2EA043?logo=shell&logoColor=white)](.shellcheckrc)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Docs](https://img.shields.io/badge/docs-live%20site-34D399?logo=githubpages&logoColor=white)](https://cheginisoroush.github.io/projdump/)
[![Try Online](https://img.shields.io/badge/try_it-in_your_browser-10B981?logo=googlechrome&logoColor=white)](https://cheginisoroush.github.io/projdump/#playground)

**English** · [فارسی](README.fa.md)

</div>

---

> [!TIP]
> 🌐 **Interactive documentation & command builder:** [cheginisoroush.github.io/projdump](https://cheginisoroush.github.io/projdump/)
>
> انتشار صفر تا صد و جذب بازدید: [docs/GOING-LIVE.md](docs/GOING-LIVE.md)

## 🎬 See it in action

<div align="center">
<img src="docs/assets/demo.svg" alt="Animated terminal demo of projdump" width="760">
</div>

## 🤔 Why?

Chatbots get smarter when they see **the whole picture**. But copy-pasting a codebase folder
by folder is slow, lossy and clumsy. `projdump` fixes that with **one command**:

- 🌳 the **directory tree**, every **source file** with correct syntax tags, plus a **summary** —
- in **one file** sized to your **token budget**, in the format your model likes best,
- generated **100% locally** — your code never touches anyone's server.

No dependencies beyond `bash 5+`, `find` and `git`. `python3` (batch
scanner) and `jq` (faster JSON quoting) are used when present and gracefully
skipped when not. **v2 is 7–25× faster** — one python3 process scans the whole
tree in a single pass instead of forking ~6 helpers per file.

## ✨ Features

- ⚡ **v2 batch scanner** — one python3 pass for the whole tree (no per-file forks), 7–25× faster on big repos
- 🌳 Built-in directory tree renderer — no `tree(1)` needed, with `--tree-depth N`
- 🎨 Language tags from 120+ file extensions (Markdown / XML highlighting)
- 🧩 `--ext-only sh,py`, repeatable `--exclude` **and** `--include`
- 📏 `--max-size` with byte-accurate comparison
- 🚫 Binary detection with a fast extension path (no `file(1)` fork for media)
- 🎯 Three formats: **Markdown**, **XML** (Claude-friendly `<file>` blocks), **JSON**
- ✂️ `--since REF` — dump only what changed since a git ref
- 💰 `--tokens-budget N` **or `--model NAME`** — fit a context window (presets for gpt-4o, claude-sonnet, gemini-2.5-pro, …)
- 📚 `--split 60k` — chunk the dump into parts sized for long chats
- ⚖️ **Weighted token estimates** — per language class, not a flat ÷ 3.5
- ⚙️ `.projdumprc` config file for your usual defaults (`--config`, `--no-config`)
- 📜 `--git-log N` — append the last N commits to the dump
- 🔀 `--sort name|size|size-desc|ext` — control the file order
- 📝 `--note` — inject a "note for the AI" block at the top of the dump
- 🗂️ Language breakdown + largest-files table in the summary
- 🌿 Git metadata in the header (`main @ a1b2c3d (dirty)`)
- 📋 Auto clipboard copy (`pbcopy` / `wl-copy` / `clip.exe` / `putclip` / `xclip` / `xsel`)
- 📊 Summary with file count, lines, size and the (weighted) token estimate
- 🛡️ Safe fences and CDATA escaping — a dump can never break itself
- ⚡ Uses `git ls-files` in repos, so `.gitignore` is respected; best-effort `.gitignore` handling outside repos too
- 🩺 `--verbose` — explains exactly why each file was skipped
- 🔍 `--list` dry run — preview exactly what would be dumped
- 🌐 [Bilingual docs site](https://cheginisoroush.github.io/projdump/) — interactive command builder, ⌘/Ctrl+K search (49 entries incl. every flag, recipe and playground preset), a cookbook of copy-paste recipes (with *Copy all* / *Download .sh* one-clicks, per-recipe 🔗 copy-link buttons and shareable `?recipe=RX` / `#recipe=RX` deep links that auto-run the recipe on load), a **simulated terminal playground** (try the CLI in your browser, nothing to install — hit **▶ demo** for a hands-free run or **⬇ transcript** to save the session), a `?` keyboard-shortcuts cheat sheet, a downloadable cheat sheet, and a token-estimator widget (English + فارسی, dark/light)

## 🚀 Quick start

```bash
git clone https://github.com/CheginiSoroush/projdump.git
cd projdump
./install.sh
exec $SHELL          # or: source ~/.bashrc
```

`install.sh` symlinks `projdump.sh` into `~/.local/bin` (override with `--prefix /usr/local`)
and installs bash + zsh completions. Nothing is copied except the completion files, so
`git pull` updates your install.

> ▶ **Impatient?** [Try projdump in your browser](https://cheginisoroush.github.io/projdump/#playground) —
> a simulated terminal with the same flags and output shapes, nothing to install.

## 🎯 Usage

```bash
cd ~/my-project

projdump                              # → my-project_dump.md
projdump --model claude-sonnet        # fit a 200k context window
projdump --split 60k                  # chunked parts for long chats
projdump -o out.md                    # custom output name
projdump --no-tree                    # skip the tree
projdump --tree-depth 2               # compact tree
projdump -e sh,bats                   # only shell files
projdump -x 'test/*' -x '*.min.js'    # skip paths (repeatable)
projdump -i 'src/*' -i 'docs/*'       # only these paths
projdump --since HEAD~5 --git-log 10  # recent changes + history
projdump --tokens-budget 60000        # fit a context window
projdump --sort size-desc             # biggest files first
projdump --list                       # preview the file list
projdump --note 'Review auth for security bugs'
projdump --max-size 100               # skip files > 100 KB
projdump --format xml                 # XML for Claude
projdump --format json                # JSON (jq-friendly)
projdump --stdout | pbcopy            # straight to the clipboard
projdump -v                           # explain skipped files
projdump -q                           # quiet: no summary line
```

> 💡 **Not sure which flags to use?** Build your command interactively in the
> [command builder](https://cheginisoroush.github.io/projdump/#builder), grab a
> copy-paste workflow from the [cookbook](https://cheginisoroush.github.io/projdump/#cookbook),
> or press `Ctrl+K` on the docs site to search every flag — and download the
> [cheat sheet](https://cheginisoroush.github.io/projdump/#options) while you're there.

<details>
<summary><b>🔧 All options</b></summary>

| Flag | Description |
|---|---|
| `[output]`, `-o, --output FILE` | Output file (default: `<project>_dump.<ext>`) |
| `-f, --format md\|xml\|json` | Output format (default `md`) |
| `--split N[k\|m]` | Write multiple parts, each ≤ N tokens (e.g. `--split 60k`) |
| `-e, --ext-only sh,md` | Only include these extensions (case-insensitive) |
| `-x, --exclude GLOB` | Skip matching paths, repeatable |
| `-i, --include GLOB` | Only matching paths, repeatable |
| `--since REF` | Only files changed since a git ref (+ untracked files) |
| `--sort KEY` | `name` (default), `size`, `size-desc`, `ext` |
| `--tokens-budget N` | Stop adding files once ~N tokens are reached |
| `--model NAME` | Preset budget for a model (see `--list-models`) |
| `--list-models` | Show available model presets and exit |
| `--max-size N` | Skip files larger than N KB (default `500`) |
| `--no-tree` | Don't include the directory tree |
| `--tree-depth N` | Limit tree depth (default: unlimited) |
| `--note TEXT` | Add a "note for the AI" block at the top |
| `--git-log N` | Include the last N commits in the dump |
| `-j, --jobs N` | Parallel workers for fallback probing (default: auto) |
| `--config FILE` | Use this config file (default: `.projdumprc`, then XDG) |
| `--no-config` | Ignore all config files |
| `--list` | Dry run: print what would be dumped, then exit |
| `--stdout` | Write to stdout instead of a file |
| `--copy` / `--no-copy` | Force / disable clipboard copy |
| `-v, --verbose` | Explain skipped files on stderr |
| `-q, --quiet` | Don't print the summary |
| `--version` | Show version |
| `-h, --help` | Show help |

</details>

<details>
<summary><b>📤 Output formats</b></summary>

**Markdown** — human-readable with per-file stats, language breakdown and a summary table.

````markdown
# 📦 my-project — Project Dump

**Generated:** 2026-10-08 12:00:00 UTC
**Path:** `/home/you/my-project`
**Git:** `main @ a1b2c3d (clean)`
...

## 📄 Source Files

### `src/main.py`

```python
print("hello")
```

<sub>1 lines · 19B</sub>

---

## 📊 Summary

| Files | Lines | Size |
|---:|---:|---:|
| 1 | 1 | 19B |

> Roughly 5 tokens (weighted per language)

### 🗂️ Languages

| Language | Files | Lines | Size |
|---|---:|---:|---:|
| python | 1 | 1 | 19B |
````

**XML** — Claude-friendly `<file>` blocks with CDATA:

```xml
<project name="my-project" path="/home/you/my-project" generated="2026-10-08T12:00:00Z" tool="projdump v2.0.0" git="main @ a1b2c3d (clean)">
  <file path="src/main.py" lang="python" lines="1" bytes="19">
    <![CDATA[
print("hello")
    ]]>
  </file>
  <stats files="1" lines="1" bytes="19" tokens="5">
    <language name="python" files="1" lines="1" bytes="19"/>
  </stats>
</project>
```

**JSON** — jq-friendly, byte-identical content (trailing newlines preserved):

```json
{"project":"my-project","files":[{"path":"src/main.py","lang":"python","lines":1,"bytes":19,"content":"print(\"hello\")\n"}],"stats":{"files":1,"lines":1,"bytes":19,"tokens":5,"languages":{"python":{"files":1,"lines":1,"bytes":19}}}}
```

</details>

## ⚡ v2 — the fast one

v1 forked ~6 helper processes per file (~40 s for a 2000-file repo). v2 batches
all of it: **one python3 process** scans every file (size, lines, binary probe,
backticks, CDATA) in a single pass, the tree is rendered in pure bash and
language tags are cached — zero forks per file:

| dump of 2000 files | v1.1.0 | v2.0.0 | speedup |
|---|---:|---:|---:|
| `--format md`   | 40.6 s | 5.5 s | **7.3×** |
| `--format xml`  | 40.6 s | 2.4 s | **17×** |
| `--format json` | 40.6 s | 1.6 s | **25×** |

Without python3, v2 falls back to one GNU `stat` batch and then to v1-style
per-file probing — still correct everywhere (BSD/macOS included, no GNU-only
`sort -z` or `numfmt`).

## ⚠️ Note on output files

The file currently being written is always excluded (even in subdirectories), and
`*_dump.md|xml|json` is in this project's `.gitignore`. If you dump to a **custom name**
(`projdump notes.md`), that file becomes a normal project file and the *next* dump will
include it — add it to `.gitignore`, or use `--exclude 'notes.md'`.

## 🧪 Test

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git
bats-core/bin/bats test/          # optional: jq, shellcheck
```

**68 functional tests** cover all three formats, adversarial filenames (quotes, newlines,
backticks, `<>&`), the config file, model presets, `--split` parts, weighted tokens
and byte-level precision of every filter.

## 🤝 Contributing

Issues and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the style rules
(shellcheck-clean, bats tests for every behaviour) and the roadmap.

## 🗑️ Uninstall

```bash
./uninstall.sh        # or: ./install.sh --uninstall
```

## ⭐ Star History

<div align="center">
<a href="https://star-history.com/#CheginiSoroush/projdump&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=CheginiSoroush/projdump&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=CheginiSoroush/projdump&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=CheginiSoroush/projdump&type=Date" width="480">
 </picture>
</a>
</div>

## 📄 License

MIT — see [LICENSE](LICENSE)

<div align="center">
<sub>Built with bash and stubbornness 🔒 Runs 100% locally — no telemetry, ever.</sub>
</div>
