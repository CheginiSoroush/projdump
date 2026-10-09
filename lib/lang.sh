#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  projdump · lib/lang.sh — language + binary detection
# ════════════════════════════════════════════════════════════════════════════
#  Sourced by projdump.sh (also usable standalone). Provides:
#
#    lang_for PATH   print a Markdown/Pygments language tag for the file —
#                    120+ extensions, plus extensionless well-known names
#                    (Dockerfile, Makefile, .gitignore, .env, …)
#    is_binary PATH  return 0 when the file looks binary; a fast extension
#                    check runs first, `grep -I` is the content fallback
#
#  Detection is deliberately dependency-free: pure bash case patterns.
#  SPDX-License-Identifier: MIT
# ════════════════════════════════════════════════════════════════════════════

# Map a file path to a Markdown/Pygments language tag.
lang_for() {
  local f="$1" base ext
  base="${f##*/}"
  ext="${base##*.}"

  # Extensionless well-known files
  case "$base" in
    Dockerfile|*.Dockerfile) echo dockerfile; return ;;
    Makefile|makefile|GNUmakefile) echo makefile; return ;;
    CMakeLists.txt|*.cmake) echo cmake; return ;;
    .gitignore|.dockerignore|.npmignore|.gitattributes) echo gitignore; return ;;
    .env|.env.*) echo bash; return ;;
    .bashrc|.bash_profile|.bash_login|.bash_logout|.profile|.zshrc|.zprofile) echo bash; return ;;
    .editorconfig|.gitconfig|.gitmodules|.npmrc) echo ini; return ;;
    LICENSE|LICENCE|NOTICE|AUTHORS|CODEOWNERS) echo text; return ;;
    *.service|*.socket|*.timer) echo ini; return ;;
    *.lock) echo text; return ;;
  esac

  case "${ext,,}" in
    sh|bash|bats)  echo bash ;;
    zsh)           echo zsh ;;
    fish)          echo fish ;;
    bat|cmd)       echo batch ;;
    ps1|psm1)      echo powershell ;;
    py|pyi|pyw)    echo python ;;
    js|mjs|cjs)    echo javascript ;;
    ts|mts|cts)    echo typescript ;;
    jsx)           echo jsx ;;
    tsx)           echo tsx ;;
    vue)           echo vue ;;
    svelte)        echo svelte ;;
    astro)         echo astro ;;
    go)            echo go ;;
    rs)            echo rust ;;
    c|h)           echo c ;;
    cpp|cc|cxx|hpp|hh|hxx) echo cpp ;;
    cs)            echo csharp ;;
    java)          echo java ;;
    kt|kts)        echo kotlin ;;
    swift)         echo swift ;;
    rb|rake|gemspec) echo ruby ;;
    php|phtml)     echo php ;;
    pl|pm)         echo perl ;;
    lua)           echo lua ;;
    r|R)           echo r ;;
    dart)          echo dart ;;
    ex|exs)        echo elixir ;;
    erl|hrl)       echo erlang ;;
    hs)            echo haskell ;;
    scala|sc)      echo scala ;;
    clj|cljs|cljc) echo clojure ;;
    elm)           echo elm ;;
    jl)            echo julia ;;
    zig)           echo zig ;;
    sol)           echo solidity ;;
    prisma)        echo prisma ;;
    html|htm|xhtml) echo html ;;
    css)           echo css ;;
    scss|sass)     echo scss ;;
    less)          echo less ;;
    json|jsonc|json5) echo json ;;
    ipynb|jsonl)   echo json ;;
    yml|yaml)      echo yaml ;;
    toml)          echo toml ;;
    ini|conf|cfg|properties) echo ini ;;
    md|markdown|mdx) echo markdown ;;
    rst)           echo rst ;;
    tex)           echo latex ;;
    sql)           echo sql ;;
    graphql|gql)   echo graphql ;;
    proto)         echo protobuf ;;
    xml|xsl|xslt)  echo xml ;;
    svg)           echo xml ;;
    csproj|props|plist|xaml|resx|wsdl) echo xml ;;
    tf|tfvars)     echo hcl ;;
    nix)           echo nix ;;
    vim)           echo vim ;;
    awk)           echo awk ;;
    sed)           echo sed ;;
    patch|diff)    echo diff ;;
    mm)            echo objectivec ;;
    *)             echo text ;;
  esac
}

# Extensions that are always binary — lets is_binary skip the `file(1)` fork
# entirely for the common cases (big win on media/build-heavy repos).
is_binary() {
  local f="$1" base mime
  [[ -f "$f" ]] || return 1

  # An empty file is valid text: `file` reports it as
  # "inode/x-empty; charset=binary", which would otherwise drop it.
  [[ -s "$f" ]] || return 1

  base="${f##*/}"
  case "${base,,}" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.ico|*.icns|*.tiff|*.psd|*.ai) return 0 ;;
    *.pdf|*.zip|*.tar|*.gz|*.tgz|*.bz2|*.xz|*.zst|*.7z|*.rar)             return 0 ;;
    *.jar|*.war|*.class|*.so|*.dylib|*.dll|*.exe|*.bin|*.o|*.a|*.obj)     return 0 ;;
    *.wasm|*.woff|*.woff2|*.ttf|*.otf|*.eot)                              return 0 ;;
    *.mp3|*.wav|*.ogg|*.flac|*.mp4|*.mkv|*.avi|*.mov|*.webm)              return 0 ;;
    *.sqlite|*.sqlite3|*.db|*.pyc|*.pyo|*.pickle)                         return 0 ;;
    *.doc|*.docx|*.xls|*.xlsx|*.ppt|*.pptx|*.odt|*.ods|*.odp)             return 0 ;;
    *.xd|*.sketch|*.fig|*.blend|*.pcap|*.parquet)                         return 0 ;;
  esac

  # Fast path: trust `file` when it is available.
  if command -v file >/dev/null 2>&1; then
    mime="$(file -b --mime "$f" 2>/dev/null || true)"
    case "$mime" in
      inode/x-empty*)                 return 1 ;;
      *"charset=binary"*)             return 0 ;;
      application/octet-stream*)      return 0 ;;
      application/zip*|application/x-executable*|application/x-archive*) return 0 ;;
      application/pdf*)               return 0 ;;
      image/*|audio/*|video/*|font/*) return 0 ;;
    esac
  fi

  # Fallback: grep -I treats a file containing NUL bytes as binary.
  LC_ALL=C grep -qI . "$f" 2>/dev/null || return 0
  return 1
}
