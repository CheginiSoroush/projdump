# projdump — bash completion
#
# Installed by install.sh into ~/.local/share/bash-completion/completions/
# (picked up automatically by bash-completion ≥ 2.0, or source it manually
# from ~/.bashrc). zsh users get a native completion: see completions/_projdump.

_projdump() {
  # With bash-completion installed, _init_completion fills cur/prev/words/cword.
  # Fallback: read them straight out of the COMP_* arrays (no external deps).
  # shellcheck disable=SC2034  # words/cword are reserved for _init_completion
  local cur prev words cword
  if declare -F _init_completion >/dev/null 2>&1; then
    _init_completion || return
  else
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  local opts="-o --output -f --format --split -e --ext-only -x --exclude \
-i --include --since --sort --tokens-budget --model --list-models --max-size \
--no-tree --tree-depth --note --git-log -j --jobs --config --no-config \
--list --dry-run --stdout --copy --no-copy -v --verbose -q --quiet \
--version -h --help"
  local exts="sh bash bats py js ts tsx go rs c cpp java rb php html css md json yml yaml toml sql xml"
  local sizes="10 50 100 200 500 1000 2000"                 # KB (--max-size)
  local budgets="30000 60000 120000 180000 900000"          # tokens (--tokens-budget)
  local models="gpt-4o gpt-4.1 o3 claude-sonnet claude-opus gemini-2.5-pro deepseek-v3 llama-3.1"
  local splits="30k 60k 100k 200k 400k 1m"

  case "$prev" in
    -o|--output)
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
      return ;;
    -f|--format)
      mapfile -t COMPREPLY < <(compgen -W "md xml json" -- "$cur")
      return ;;
    -e|--ext-only)
      mapfile -t COMPREPLY < <(compgen -W "$exts" -- "$cur")
      return ;;
    --max-size)
      mapfile -t COMPREPLY < <(compgen -W "$sizes" -- "$cur")
      return ;;
    --tokens-budget)
      mapfile -t COMPREPLY < <(compgen -W "$budgets" -- "$cur")
      return ;;
    --model)
      mapfile -t COMPREPLY < <(compgen -W "$models" -- "$cur")
      return ;;
    --split)
      mapfile -t COMPREPLY < <(compgen -W "$splits" -- "$cur")
      return ;;
    --sort)
      mapfile -t COMPREPLY < <(compgen -W "name size size-desc ext" -- "$cur")
      return ;;
    --tree-depth|--git-log|-j|--jobs)
      mapfile -t COMPREPLY < <(compgen -W "1 2 3 5 10 20" -- "$cur")
      return ;;
    --config)
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
      return ;;
    -x|--exclude|-i|--include)
      mapfile -t COMPREPLY < <(compgen -d -- "$cur")
      return ;;
    --since)
      # complete with git refs when inside a repository
      local refs
      refs="$(git branch --format='%(refname:short)' 2>/dev/null; printf 'HEAD\nHEAD~1\nHEAD~5\nmain\nmaster')"
      mapfile -t COMPREPLY < <(compgen -W "$refs" -- "$cur")
      return ;;
  esac

  case "$cur" in
    -*) mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur") ;;
    *)  mapfile -t COMPREPLY < <(compgen -f -- "$cur") ;;
  esac
}

complete -F _projdump projdump
