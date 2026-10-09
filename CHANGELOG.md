# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Documentation website (`docs/`) — bilingual English/فارسی with full RTL support, dark/light theme, animated terminal demo, interactive **command builder**, searchable options reference, GitHub Pages deployment guide and FAQ. Ships as a finished static site (no build step) so GitHub Pages can serve it straight from `/docs`
- Docs site: **⌘/Ctrl+K search palette** — fuzzy-free instant search across all sections, every CLI flag (searching English *and* Persian descriptions) and the FAQ; full keyboard navigation (↑/↓/↵/esc, `/` shortcut), bilingual labels, ARIA combobox semantics, jumping to a flag scrolls to its table row and flashes it
- Docs site: **reading-progress bar** under the nav (rAF-throttled, RTL-aware gradient) and **copy-anchor `#` buttons** on every section heading (copies a shareable URL, updates the hash)
- Docs site: **downloadable cheat sheet** — one click builds `projdump-cheatsheet.md` from the live options table (locale-aware descriptions, pipes escaped, invisible bidi marks stripped) and downloads it
- Docs site: hover accent on options-table rows, `kbd` chip styling for shortcut hints, mobile-optimised palette layout
- Docs site: **Cookbook section** — six copy-paste recipes for real workflows (briefing an AI on a bug, fitting a repo into a context window, reviewing only what changed, auditing the language mix, piping JSON into `jq`, frontend-only snapshots); every command verified against the real CLI and searchable from the palette
- Docs site: **version pill** in the nav (links to the changelog; hidden on smaller viewports)
- Docs site: **simulated terminal playground** (#playground) — visitors can type real commands (`projdump --list`, `--format xml --note …`, `--tokens-budget`, `-v -e py`, `--since main`, `help`, `clear`, plus `ls`/`pwd`/`git status` easter eggs) against a small virtual git project; the simulation mirrors the actual CLI's flags, validation errors (`unrecognized option`, bad revision, missing argument), first-file-kept budget semantics, verbose skip reasons and truncated-but-faithful md/xml/json output shapes. Includes ↑/↓ history, Tab flag completion with ambiguous-match listing, six one-click preset chips, a "▶ Try it in the playground" CTA from the builder, and a SIMULATED badge so nobody mistakes it for real bash
- Docs site: **print stylesheet** — nav/chrome hidden, deploy accordions expand, scroll containers release their height, code blocks switch to ink-friendly white; the options table and cookbook print as a clean reference
- Docs site: the playground now understands **one pipe stage** — `| jq FILTER` works with `.`, `.stats`, `.stats.languages`, `.files | length` and `.files[].path` (matching the real CLI's JSON shape), unknown filters get an honest error listing what's available, and non-jq stages get a `command not found` hint
- Docs site: every cookbook card gained a **"▶ Try" button** that runs that recipe's exact command in the playground (line-continuations joined automatically) — including the R5 pipe; buttons re-localise on language switch
- Docs site: playground Markdown output is lightly syntax-highlighted (accent headings, dimmed fences); READMEs gained a "try it in your browser" badge linking to the playground
- Docs site: **"▶ demo" replay chip** in the playground — auto-types the budget recipe character-by-character (asciinema-style) and runs it hands-free; click again mid-typing to stop and take over, any keypress or preset chip cancels, `prefers-reduced-motion` fills instantly, and the label/title localise in both languages
- Docs site: **cookbook toolbar** — a `Copy all` button puts all six recipes on the clipboard as a commented, ready-to-run shell block (headers derived live from the card titles, so they follow the site language), and a `Download .sh` button saves `projdump-recipes.sh` with a `#!/usr/bin/env bash` + `set -euo pipefail` preamble; both confirm via toast
- Docs site: each cookbook card shows a mono **flag tag line** (`--format xml · --note · -x` …) and the section gained a "verified against the real CLI" note; keyboard `:focus-visible` rings added to chips, try/copy/tab and toolbar buttons; the toolbar is excluded from print output
- Docs site: **recipe deep links** — every "▶ Try" click, palette ▶-run and Tab-run rewrites the address bar to `?recipe=RX`, and loading the site with that param auto-plays the recipe: the card glows, a toast announces the run in the site language, then the playground executes the exact command — demos are now shareable URLs. Hash form (`#recipe=RX`) works too, for platforms that strip query strings
- Docs site: every recipe card gained a **🔗 Copy link button** — copies the parent-page deep link (`origin + path + ?recipe=RX`) with clipboard fallback, ✓ state on the button and a localized toast; buttons re-localise on language switch (old ones are properly removed — no accumulation)
- Docs site: the playground title bar gained a **⬇ transcript** button that downloads the whole session (`projdump-playground.txt`) with an explicit "SIMULATED output, not a real dump" header line; hidden in print output
- Docs site: **keyboard shortcuts cheat sheet** — press `?` anywhere (or click the `? shortcuts` hint in the palette footer) for a bilingual overlay listing every shortcut, grouped into "Everywhere" (Ctrl+K, /, ?, ↑↓, ↵, ⇥ run recipe, esc) and "In the playground input" (↑↓ history, Tab completion); Esc / backdrop click / `?` again close it, focus is restored on close, and it's excluded from print
- Docs site: the palette gained a fifth group, **Playground presets** — all six preset chips are indexed with their exact command as the sub-label (49 entries total now); Enter scrolls to the playground and runs the preset, so `budget`, `xml + note`, `-v -e py`, `--since main` and friends are reachable straight from search
- Docs site: palette recipe rows gained a **second action** — a ▶ run chip on each recipe row (plus `Tab` on a selected row) runs that recipe in the playground straight from search; a contextual `⇥ run recipe` hint appears in the palette footer only while a recipe row is selected
- `docs/GOING-LIVE.md` — a zero-to-100 bilingual guide: publishing to GitHub Pages, custom domain, SEO/share cards and a traffic-growth playbook
- Animated repository banner and terminal-demo SVGs, a generated logo and a 1200×630 social preview image (`docs/assets/`)
- Man-page-style header documentation for every shell script (synopsis, design rules, exit codes, environment, examples)
- `install.sh --prefix=DIR` form, matching the existing `uninstall.sh` behaviour

### Fixed

- Docs site: left-to-right mark characters (U+200E) had leaked into inline `style` attributes, silently invalidating `var(--bg-soft)` / `var(--border)` and stripping the alternating background from the Install, Formats, Deploy and Compare sections; attributes are now clean while Persian text keeps its bidi marks
- `install.sh --help` printed the script's own `set -euo pipefail` line at the end of the help text; the help range now matches the header block exactly. `uninstall.sh --help` now prints the full usage header instead of a single line
- Docs site: the nav links and the search-trigger `Ctrl K` hint could wrap onto two lines once the Recipes link and version pill joined the nav — links and kbd chips are now `white-space:nowrap` and the hamburger/mobile menu takes over below 1120px
- Docs site: recipe code blocks used a translucent copy button that long command lines visibly slid under; the button now matches the code background
- Docs site: inline flag chips in feature cards, FAQ answers and the changelog could split mid-token across lines (`--` / `include`) on narrow cards; word-joiners now make each flag unbreakable while text still wraps between chips
- Docs site (internal): the playground's virtual clock variable was declared as `PG_PAL_NOW` but referenced as `PG_NOW` (would have thrown on the first simulated dump) and the `--list` path returned `undefined` where the summary assignment expected an object — both caught in self-review before browser testing

## [1.1.0] - 2026-10-08

### Added

- `--list` / `--dry-run` — preview exactly which files would be dumped, with sizes, line counts and the token total
- `-i, --include GLOB` — the inverse of `--exclude`: only paths matching at least one include glob are dumped (repeatable)
- `--since REF` — dump only files changed since a git ref (diff against the working tree + untracked files), with early, clear errors outside repos or for bad refs
- `--tokens-budget N` — stop adding files once the estimated token count reaches N (first file is always kept; combine with `--sort size` to pack efficiently)
- `--sort name|size|size-desc|ext` — control file order; `size-desc` puts the biggest files first
- `--note TEXT` — inject a "Note for the AI" block at the top of the dump (Markdown, XML `<note>` and a JSON `"note"` field)
- `-v, --verbose` — print every skipped file and the reason (binary, too large, excluded, filtered, over budget, …) plus skip totals in the summary
- `-o/--output`, `-f/--format`, `-e/--ext-only`, `-x/--exclude` short options
- Language breakdown in the summary: Markdown table, `<language …/>` elements in XML and `stats.languages` in JSON, ordered by size
- "Largest files" table (top 5) in the Markdown summary
- Git metadata in the header: `**Git:** main @ a1b2c3d (dirty)` (also `git=` attribute in XML and a `"git"` field in JSON)
- `**Scope:**` header line (and `since=`/`"since"`) when dumping with `--since`
- WSL (`clip.exe`) and Cygwin (`putclip`) clipboard support
- Byte-level binary fast path: common binary extensions (images, archives, fonts, media, …) are rejected without a `file(1)` fork
- `uninstall.sh --prefix=DIR` form and clean argument validation
- `install.sh` now syntax-checks `lib/*.sh` too
- More default junk directories pruned in non-git mode (`.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.cache`, `coverage`, `.pytest_cache`, `.mypy_cache`, `.idea`, `.vscode`)
- More language tags: `batch`, `cmake`, `diff`, `elm`, `julia`, `zig`, `solidity`, `prisma`, `astro`, `objectivec`, plus dotfiles (`.bashrc`, `.editorconfig`, `.gitconfig`, …) and Office/XML/JSON-adjacent extensions

### Fixed

- **bash 5.2 corruption**: bash 5.2 enables `patsub_replacement` by default, which made a bare `&` in `${var//pat/repl}` replacements expand to the matched text — `xml_escape` then produced `"quot;` instead of `&quot;`, silently corrupting XML output whenever a path contained `<`, `>` or `"` (latent in v1.0.0, invisible to CI because fixture paths were clean). The option is now explicitly disabled and the escaping is covered by a regression test
- A dump written to a **subdirectory** (`projdump sub/out.md`) could include itself on the next run — exclusion now compares the full relative path, not just the basename
- `--max-size` compared floored kilobytes, so a 1536-byte file slipped through `--max-size 1`; the comparison is now byte-accurate
- JSON file content lost **all** trailing newlines (`"$(cat file)"` strips them); contents are now streamed via stdin and byte-identical to the source — the pure-awk fallback reconstructs trailing newlines exactly
- Extension detection misread paths like `my.dir/file` (dot in a directory name) — the extension now comes from the basename
- `--ext-only` values now tolerate spaces around commas (`sh, py`)
- `uninstall.sh --prefix` without a value aborted with a cryptic `set -e` shift error; it now fails with a clear message
- An output path that is an existing directory (or ends with `/`) no longer makes `mv` hide the dump *inside* the directory; both cases fail with clear errors, and missing parent directories are created automatically
- `--stdout`/`--list` combined with an output path now warn instead of silently ignoring it
- `wc -l` undercounted files without a trailing newline; line counts now include an unterminated last line
- Temporary list files could leak when the run was interrupted; the pipeline is now temp-free except for the output file

### Changed

- Files are measured (size + lines) exactly once and reused across filters, writers and stats — fewer forks, faster on big repos
- `tree --fromfile` output is captured with a single invocation instead of a probe run plus a real run
- Per-file paths in Markdown dumps are shown without the `./` prefix in non-git mode, consistent with git mode

## [1.0.0] - 2026-10-04

### Added

- `projdump.sh` — dumps a whole project into one file
- Output formats: Markdown, XML, JSON
- Directory tree section (`tree(1)` when available, built-in fallback otherwise)
- Language detection covering 90+ extensions (54 language tags) (`lib/lang.sh`)
- Binary detection via `file --mime` with a `grep -I` fallback (`lib/lang.sh`)
- Filtering: `--ext-only`, `--exclude` (repeatable), `--max-size`
- `--stdout`, `--copy` / `--no-copy`, `-q/--quiet`
- Summary with file count, lines, size and a rough token estimate
- Clipboard auto-copy for macOS, Wayland and X11
- Respects `.gitignore` through `git ls-files` inside git repos
- `install.sh` / `uninstall.sh` with `--prefix` support
- bash and zsh completions
- bats test suite (`test/`) and GitHub Actions CI (ShellCheck + tests + smoke)

### Fixed (relative to the first draft of the script)

- The dump file is always excluded, so a dump can never contain (or append to) itself
- JSON output is now valid: comma placement fixed and content is escaped with `jq`/`python3`
- XML attributes are escaped, and `]]>` inside a file is CDATA-split instead of corrupting the document
- The tree no longer requires `tree(1)` and no longer ignores `--no-tree` in XML mode
- Markdown fences grow past any ``` ``` ``` run inside a file instead of breaking the block
- NUL-safe file collection (`find -print0` / `git ls-files -z`) for paths with spaces or newlines
- `stat` works on BSD/macOS as well as GNU coreutils
- `SCRIPT_DIR` resolves symlinks (absolute *and* relative targets), so `lib/` is still found when invoked through the `~/.local/bin/projdump` symlink

[Unreleased]: https://github.com/CheginiSoroush/projdump/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/CheginiSoroush/projdump/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/CheginiSoroush/projdump/releases/tag/v1.0.0
