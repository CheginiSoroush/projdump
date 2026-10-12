#!/usr/bin/env bats
# ════════════════════════════════════════════════════════════════════════════
#  test/helpers.bats — shared setup for every suite file
#  Provides: REPO (a fresh git fixture), a() to add files, run_pd()
# ════════════════════════════════════════════════════════════════════════════
PD="$BATS_TEST_DIRNAME/../projdump.sh"

new_repo() {
  REPO="$(mktemp -d "${BATS_TEST_TMPDIR}/repo.XXXXXX")"
  cd "$REPO" || exit 1
  git init -q
  git config user.name  "test"
  git config user.email "test@example.com"
}

# add + commit one file:  a path "content"
a() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; git add -A; git -c commit.gpgsign=false commit -qm "add $1"; }

# run projdump quietly, output on stdout
run_pd() { run bash "$PD" --quiet --no-copy --no-config --stdout "$@"; }
