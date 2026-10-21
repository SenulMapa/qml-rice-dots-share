#!/usr/bin/env bash
# Tests for the pre-push privacy gate (.githooks/pre-push + tools/privacy-audit.sh).
# Every case builds throwaway repos under mktemp -d with a bare repo as origin.
# Nothing here touches a real remote; the hook is run directly with the stdin
# git would send, never via `git push`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAKE_TERM="fakeuser-zz9"
ZERO=0000000000000000000000000000000000000000
PASS=0
FAILN=0
WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

# new_repo <name>: sets REPO (work repo) and BARE (origin). The work repo gets
# a copy of the gate, a base commit that origin/master points at, and an
# untracked denylist (gitignored in the real repo, so never committed).
new_repo() {
  local name="$1"
  BARE="$WORK_ROOT/$name-origin.git"
  REPO="$WORK_ROOT/$name"
  git init -q --bare "$BARE"
  git init -q -b master "$REPO"
  git -C "$REPO" config user.name "test"
  git -C "$REPO" config user.email "test@example.com"
  mkdir -p "$REPO/tools" "$REPO/.githooks"
  cp "$ROOT/tools/privacy-audit.sh" "$ROOT/tools/privacy-allowlist.txt" "$REPO/tools/"
  cp "$ROOT/.githooks/pre-push" "$REPO/.githooks/"
  # The real repo gitignores the denylist. Mirror that, or `git add -A` sweeps
  # it into a commit and a branch switch deletes it, so the personal-ID scan
  # silently does nothing and every case passes for the wrong reason.
  printf 'tools/.personal-denylist\n' >"$REPO/.gitignore"
  echo base >"$REPO/README"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm base
  git -C "$REPO" remote add origin "$BARE"
  git -C "$REPO" update-ref refs/remotes/origin/master master
  printf '%s\n' "$FAKE_TERM" >"$REPO/tools/.personal-denylist"
  git -C "$REPO" check-ignore -q tools/.personal-denylist || { echo "fixture: denylist not ignored" >&2; exit 2; }
}

# commit_file <repo> <path> <content> <message>
commit_file() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -qm "$4"
}

# hook_push <repo> <local-ref>: feeds the hook the stdin git sends on push.
hook_push() {
  local repo="$1" ref="$2" sha
  sha="$(git -C "$repo" rev-parse "$ref")"
  (cd "$repo" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$ref" "$sha" "$ref" "$ZERO" \
    | ./.githooks/pre-push origin "$BARE")
}

# expect_exit <want-rc> <log-name> <cmd...>: runs cmd, compares exit code, prints log tail on mismatch.
expect_exit() {
  local want="$1" log="$WORK_ROOT/$2.log"
  shift 2
  "$@" >"$log" 2>&1
  local rc=$?
  if [ "$rc" -eq "$want" ]; then
    return 0
  fi
  echo "    expected exit $want, got $rc; log tail:"
  tail -n 25 "$log" | sed 's/^/    | /'
  return 1
}

run_case() {
  local name="$1"
  if "$name"; then
    echo "PASS $name"
    PASS=$((PASS+1))
  else
    echo "FAIL $name"
    FAILN=$((FAILN+1))
  fi
}

clean_master_with_dirty_local_branch_passes() {
  new_repo c1
  git -C "$REPO" switch -q -c dirty
  commit_file "$REPO" leak.txt "$FAKE_TERM" "dirty: leaks term"
  git -C "$REPO" switch -q master
  commit_file "$REPO" clean.txt "clean change" "clean master commit"
  # Precondition: the dirty branch really is dirty, i.e. a full-history audit
  # sees the term. Without this, a pass could come from a broken fixture.
  expect_exit 1 c1pre bash "$REPO/tools/privacy-audit.sh" "$REPO" --history || return 1
  expect_exit 0 c1 hook_push "$REPO" master
}

dirty_branch_push_fails() {
  new_repo c2
  git -C "$REPO" switch -q -c dirty
  commit_file "$REPO" leak.txt "$FAKE_TERM" "dirty: leaks term"
  expect_exit 1 c2 hook_push "$REPO" dirty
}

dirty_blob_in_range_but_not_tip_fails() {
  new_repo c3
  commit_file "$REPO" tmp.txt "$FAKE_TERM" "add term"
  git -C "$REPO" rm -q tmp.txt
  git -C "$REPO" commit -qm "remove term"
  expect_exit 1 c3 hook_push "$REPO" master
}

history_mode_uncapped() {
  new_repo h4
  # Oldest commit holds the term. rev-list lists newer commits' blobs first,
  # so this blob lands after the 5000th object and only an uncapped scan sees it.
  commit_file "$REPO" old.txt "$FAKE_TERM" "old term blob"
  mkdir -p "$REPO/gen"
  local i
  for i in $(seq 1 5005); do
    printf 'f%s\n' "$i" >"$REPO/gen/f$i"
  done
  git -C "$REPO" rm -q old.txt
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "bulk objects"
  expect_exit 1 h4 bash "$REPO/tools/privacy-audit.sh" "$REPO" --history
}

bad_range_fails_closed() {
  new_repo c5
  expect_exit 1 c5 bash "$REPO/tools/privacy-audit.sh" "$REPO" --range "no-such-ref --not --remotes"
}

# make_bin <dir> [keep-trufflehog]: a PATH directory holding every /usr/bin
# program except the external secret scanners, so `command -v` cannot find
# gitleaks at all, and trufflehog only when keep-trufflehog is given.
make_bin() {
  local dir="$1" keep_th="${2:-}" f
  mkdir -p "$dir"
  for f in /usr/bin/*; do
    case "$(basename "$f")" in
      gitleaks|trufflehog) continue ;;
    esac
    ln -sf "$f" "$dir/"
  done
  if [ -n "$keep_th" ]; then
    ln -sf "$(command -v trufflehog)" "$dir/trufflehog"
  fi
}

missing_denylist_fails_in_push_mode() {
  new_repo d1
  commit_file "$REPO" clean.txt "clean change" "clean master commit"
  rm -f "$REPO/tools/.personal-denylist"
  expect_exit 1 d1 hook_push "$REPO" master || return 1
  grep -q 'personal-denylist' "$WORK_ROOT/d1.log" || return 1
  # A denylist with only comments has no terms, so the scan cannot run either.
  printf '# no terms here\n' >"$REPO/tools/.personal-denylist"
  expect_exit 1 d1b hook_push "$REPO" master || return 1
}

neither_scanner_fails_in_push_mode() {
  new_repo s1
  commit_file "$REPO" clean.txt "clean change" "clean master commit"
  make_bin "$WORK_ROOT/bin-none"
  expect_exit 1 s1 env PATH="$WORK_ROOT/bin-none" bash "$REPO/tools/privacy-audit.sh" "$REPO" --range "master --not --remotes" || return 1
  grep -q 'secret-scanner-missing' "$WORK_ROOT/s1.log"
}

range_trufflehog_alone_catches_secret() {
  if ! command -v trufflehog >/dev/null 2>&1; then
    echo "    (trufflehog not installed; case not applicable)"
    return 0
  fi
  new_repo s2
  # sk_live_ keys are not in the built-in regex list, so only a scanner can catch this.
  commit_file "$REPO" creds.txt "stripe = sk_live_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)" "add key"
  make_bin "$WORK_ROOT/bin-th" keep
  expect_exit 1 s2 env PATH="$WORK_ROOT/bin-th" bash "$REPO/tools/privacy-audit.sh" "$REPO" --range "master --not --remotes" || return 1
  grep -q 'FAIL *| trufflehog:' "$WORK_ROOT/s2.log"
}

echo "== test-privacy-gate: ROOT=$ROOT =="
run_case clean_master_with_dirty_local_branch_passes
run_case dirty_branch_push_fails
run_case dirty_blob_in_range_but_not_tip_fails
run_case history_mode_uncapped
run_case bad_range_fails_closed
run_case missing_denylist_fails_in_push_mode
run_case neither_scanner_fails_in_push_mode
run_case range_trufflehog_alone_catches_secret
echo "Summary: $PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
