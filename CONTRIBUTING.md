# Contributing

Thanks for your interest in projdump! 🎉

## Development setup

```bash
git clone https://github.com/CheginiSoroush/projdump.git
cd projdump

# test runner
git clone --depth 1 https://github.com/bats-core/bats-core.git
bats-core/bin/bats test/

# linter (Linux)
sudo apt install shellcheck          # or: pip install shellcheck-py
shellcheck -x projdump.sh install.sh uninstall.sh lib/*.sh completions/projdump
```

## Before you open a PR

1. `shellcheck -x` is clean (CI enforces it, `severity: warning`)
2. `bats test/` passes
3. `./projdump.sh --stdout` still works on this repo itself
4. New flags are documented in `README.md`, `README.fa.md`, `usage()` and `completions/projdump`
5. Anything user-visible gets a line in `CHANGELOG.md` under `[Unreleased]`

## Style guide

- Bash 5+, `set -euo pipefail` in every script
- `[[ ... ]]`, quoted expansions, `printf` over `echo -e` outside the logging helpers
- Optional tools must degrade gracefully — never hard-require `tree`, `jq`, `python3`, `xclip`
- File lists are NUL-separated end to end (`find -print0`, `git ls-files -z`, `read -d ''`)
- Never end a function (or an `if` body) with a bare `(( ... )) && cmd` — under `set -e`
  a false left side would leak status; end with `return 0` or use `if`
- Measure each file once (size + lines) and reuse the numbers; don't re-fork `stat`/`wc`
- Guard `printf '%s\0' "${ARR[@]}"` against empty arrays — with no arguments `printf`
  reuses the format once and emits a lone NUL byte
- Keep functions small and single-purpose; document non-obvious ones

## Commit convention

[Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use |
|---|---|
| `feat:` | new feature |
| `fix:` | bug fix |
| `docs:` | documentation only |
| `test:` | tests only |
| `refactor:` | code change, no behaviour change |
| `chore:` | maintenance, CI, deps |

Example: `feat: add --exclude glob filter`

## Ideas / roadmap

- [x] `--include` as the inverse of `--exclude` (v1.1.0)
- [x] `--tokens-budget N` — stop adding files once N tokens are reached (v1.1.0)
- [x] `--diff` — dump only files changed since a git ref (shipped as `--since REF`, v1.1.0)
- [ ] `--zip` — write a `.zip` instead of a single file
- [ ] `--format html` — self-contained HTML view with a collapsible file tree
- [ ] `.projdumprc` — project-local defaults (excludes, budget, sort)
- [ ] `--stdin` mode — read a file list from stdin instead of scanning
