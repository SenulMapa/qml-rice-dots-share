#!/usr/bin/env bash
# tools/privacy-audit.sh <repo-path> [--history | --range "<rev-list args>"]
#
# Deterministic, offline (no network) pre-publish gate. Exits 1 on any FAIL.
# WARN findings (attack-surface hygiene) never fail the run.
#
# Modes:
#   (default)   working tree + history-free checks (what is on disk)
#   --history   the default checks, plus every blob reachable from ANY ref.
#               Uncapped. For manual full audits.
#   --range R   only what a push would publish: every object reachable from
#               R (a rev-list argument string, e.g. "<sha> --not --remotes").
#               Working-tree checks are skipped; unpushed files never leave.
#
# Checks:
#   1. Secrets       -> gitleaks + trufflehog (if installed) + built-in regexes
#   2. Personal IDs   -> tools/.personal-denylist (gitignored, not shipped)
#   3. Metadata leaks -> EXIF/GPS, stray .git/logs/history fixtures, bad author emails
#   4. Attack surface -> curl|sh, sudo, chmod 777, unpinned downloads, telemetry (WARN only)
set -uo pipefail

REPO="${1:-}"
[ $# -gt 0 ] && shift
HISTORY=0
RANGE_MODE=0
RANGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --history) HISTORY=1 ;;
    --range)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "--range needs a non-empty rev-list argument string" >&2
        exit 1
      fi
      RANGE_MODE=1
      RANGE="$2"
      shift
      ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
if [ "$HISTORY" = "1" ] && [ "$RANGE_MODE" = "1" ]; then
  echo "--history and --range are mutually exclusive" >&2
  exit 1
fi

# -e, not -d: a linked worktree has .git as a file.
if [ -z "$REPO" ] || [ ! -e "$REPO/.git" ]; then
  echo "usage: $0 <repo-path> [--history | --range \"<rev-list args>\"]  (repo-path must be a git repo)" >&2
  exit 1
fi
REPO="$(cd "$REPO" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DENYLIST="$SCRIPT_DIR/.personal-denylist"
ALLOWLIST="$SCRIPT_DIR/privacy-allowlist.txt"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

FAILS=0
WARNS=0
ALLOWED=0
declare -a ROWS

# Reviewed-false-positive check for regex-secret findings ONLY. Never used
# for gitleaks/trufflehog findings or personal-id/denylist hits -- callers
# of this function are limited to the two regex-secret blocks below.
is_allowlisted() {
  local h="$1"
  [ -f "$ALLOWLIST" ] || return 1
  grep -qE "^sha256:${h}([[:space:]]|\$)" "$ALLOWLIST" 2>/dev/null
}

trimmed_sha256() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sha256sum | cut -d' ' -f1
}

row() { ROWS+=("$1|$2|$3|$4"); } # severity|check|location|detail

mask() {
  # mask a secret to first 4 chars + length marker
  local s="$1" n=${#1}
  if [ "$n" -le 4 ]; then printf '%s' "****"; else printf '%s...(%dchars)' "${s:0:4}" "$n"; fi
}

# history_blobs <outfile> <rev-list args...>
# Writes "<blob-sha> <path>" for every blob reachable from the rev-list args.
# No cap: the whole set is audited. Returns rev-list's exit status so an
# unusable range fails closed instead of auditing nothing.
history_blobs() {
  local out="$1"
  shift
  git -C "$REPO" rev-list --objects --filter=object:type=blob "$@" 2>"$TMPD/revlist.err" \
    | awk 'index($0, " ") > 0' >"$out"
  return "${PIPESTATUS[0]}"
}

# exif_check <image-file> <label>: flags GPS/author/device metadata.
exif_check() {
  local img="$1" label="$2" meta
  if command -v exiftool >/dev/null 2>&1; then
    meta="$(exiftool -GPSLatitude -GPSLongitude -Author -Creator -Software -Make -Model "$img" 2>/dev/null | grep -v '^\s*$')"
    if [ -n "$meta" ]; then
      row "FAIL" "exif-metadata" "$label" "$(echo "$meta" | tr '\n' ';' | cut -c1-120)"
      FAILS=$((FAILS+1))
    fi
  elif python3 -c "import PIL" >/dev/null 2>&1; then
    meta="$(python3 - "$img" <<'PY' 2>/dev/null
from PIL import Image
try:
    im = Image.open(__import__("sys").argv[1])
    exif = im.getexif()
    if exif and len(exif):
        print("has-exif")
except Exception:
    pass
PY
)"
    if [ "$meta" = "has-exif" ]; then
      row "WARN" "exif-metadata" "$label" "EXIF present (exiftool not installed; verify manually)"
      WARNS=$((WARNS+1))
    fi
  else
    row "WARN" "exif-metadata" "$label" "no exiftool/PIL available; flagged for manual review"
    WARNS=$((WARNS+1))
  fi
}

SECRET_PATTERNS=(
  'sk-[A-Za-z0-9]{20,}'
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'gh[pousr]_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AIza[0-9A-Za-z_-]{20,}'
  'xox[abp]-[A-Za-z0-9-]{10,}'
  'AKIA[0-9A-Z]{12,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'Bearer [A-Za-z0-9._~+/=-]{10,}'
  '[Aa][Pp][Ii][_-]?[Kk][Ee][Yy][[:space:]]*[:=]'
  '[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[:=]'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  'https://hooks\.slack\.com/services/[A-Za-z0-9/]+'
  'https://discord(app)?\.com/api/webhooks/[A-Za-z0-9/]+'
  'api\.kie\.ai/[A-Za-z0-9/_-]*key'
  'figma\.com/[^ ]*(access_token|token)=[A-Za-z0-9]+'
  'api\.openweathermap\.org/[^ ]*appid=[A-Za-z0-9]+'
)
# One alternation of every pattern: a cheap per-blob prefilter.
SECRET_ANY="$(IFS='|'; echo "${SECRET_PATTERNS[*]}")"

# Denylist split for batched history matching: alnum terms match on word
# boundaries, everything else as a plain substring (same rules as the
# working-tree scan below).
DENY_SUB="$TMPD/deny-sub"
DENY_WORD="$TMPD/deny-word"
: >"$DENY_SUB"
: >"$DENY_WORD"
if [ -f "$DENYLIST" ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    case "$term" in \#*) continue ;; esac
    if [[ "$term" =~ ^[A-Za-z0-9]+$ ]]; then
      printf '%s\n' "$term" >>"$DENY_WORD"
    else
      printf '%s\n' "$term" >>"$DENY_SUB"
    fi
  done <"$DENYLIST"
fi

echo "== privacy-audit: $REPO (history=$HISTORY, range=${RANGE:-none}) =="

# Objects the audit covers in history/range modes: one "<blob> <path>" per line.
if [ "$HISTORY" = "1" ] || [ "$RANGE_MODE" = "1" ]; then
  if [ "$RANGE_MODE" = "1" ]; then
    read -ra AUDIT_ARGS <<<"$RANGE"
  else
    AUDIT_ARGS=(--all)
  fi
  BLOB_LIST="$TMPD/blobs.txt"
  if ! history_blobs "$BLOB_LIST" "${AUDIT_ARGS[@]}"; then
    row "FAIL" "rev-list" "${RANGE:---all}" "could not enumerate objects: $(head -c 160 "$TMPD/revlist.err" | tr '\n' ' ')"
    FAILS=$((FAILS+1))
    : >"$BLOB_LIST"
  fi
fi

# ---------------------------------------------------------------------------
# 1a. gitleaks
# ---------------------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  GL_OUT="$(mktemp)"
  if [ "$RANGE_MODE" = "1" ]; then
    ( cd "$REPO" && gitleaks git --no-banner -f json -r "$GL_OUT" --log-opts "$RANGE" . ) >"$TMPD/gitleaks.log" 2>&1
    GL_RC=$?
  elif [ "$HISTORY" = "1" ]; then
    ( cd "$REPO" && gitleaks git --no-banner -f json -r "$GL_OUT" . ) >"$TMPD/gitleaks.log" 2>&1
    GL_RC=$?
  else
    ( cd "$REPO" && gitleaks dir --no-banner -f json -r "$GL_OUT" . ) >"$TMPD/gitleaks.log" 2>&1
    GL_RC=$?
  fi
  # 0 = clean, 1 = leaks found (parsed below); anything else is a scanner error.
  if [ "$GL_RC" -gt 1 ]; then
    row "FAIL" "gitleaks-error" "-" "gitleaks exited $GL_RC; see $TMPD/gitleaks.log"
    FAILS=$((FAILS+1))
  fi
  if [ -s "$GL_OUT" ] && [ "$(cat "$GL_OUT")" != "[]" ] && [ "$(cat "$GL_OUT")" != "null" ]; then
    COUNT=$(grep -o '"RuleID"' "$GL_OUT" | wc -l)
    if [ "$COUNT" -gt 0 ]; then
      while IFS=$'\t' read -r file line rule secret; do
        row "FAIL" "gitleaks:$rule" "$file:$line" "$(mask "$secret")"
        FAILS=$((FAILS+1))
      done < <(python3 - "$GL_OUT" <<'PY' 2>/dev/null
import json,sys
try:
    data=json.load(open(sys.argv[1]))
except Exception:
    data=[]
for f in data:
    print(f.get("File",""),f.get("StartLine",""),f.get("RuleID",""),f.get("Secret",""),sep="\t")
PY
)
    fi
  fi
  rm -f "$GL_OUT"
else
  row "WARN" "gitleaks" "-" "gitleaks not installed; secret scan incomplete"
  WARNS=$((WARNS+1))
fi

# ---------------------------------------------------------------------------
# 1b. trufflehog
# ---------------------------------------------------------------------------
if command -v trufflehog >/dev/null 2>&1; then
  TH_OUT="$(mktemp)"
  if [ "$RANGE_MODE" = "1" ]; then
    # trufflehog takes one --since-commit, not a rev-list range. Scan from the
    # first remote-reachable boundary of the range up to the tip. That is a
    # superset of the range's commits, so nothing being published is skipped.
    # --fail makes rc 183 mean "findings", separating it from scanner errors.
    TH_TIP="${AUDIT_ARGS[0]}"
    TH_BASE="$(git -C "$REPO" rev-list --boundary "${AUDIT_ARGS[@]}" 2>/dev/null | sed -n 's/^-//p' | head -1)"
    TH_SINCE=()
    if [ -n "$TH_BASE" ]; then TH_SINCE=(--since-commit "$TH_BASE"); fi
    trufflehog git "file://$REPO" "${TH_SINCE[@]}" --branch "$TH_TIP" --fail --no-verification --no-update --json >"$TH_OUT" 2>"$TMPD/trufflehog.log"
    TH_RC=$?
    if [ "$TH_RC" -ne 0 ] && [ "$TH_RC" -ne 183 ]; then
      row "FAIL" "trufflehog-error" "-" "trufflehog exited $TH_RC over the range; see $TMPD/trufflehog.log"
      FAILS=$((FAILS+1))
    fi
  elif [ "$HISTORY" = "1" ]; then
    trufflehog git "file://$REPO" --no-verification --no-update --json >"$TH_OUT" 2>"$TMPD/trufflehog.log"
  else
    trufflehog filesystem "$REPO" --no-verification --no-update --json >"$TH_OUT" 2>"$TMPD/trufflehog.log"
  fi
  if [ -s "$TH_OUT" ]; then
    while IFS=$'\t' read -r detector file commit raw; do
      row "FAIL" "trufflehog:$detector" "${file:-$commit}" "$(mask "$raw")"
      FAILS=$((FAILS+1))
    done < <(python3 - "$TH_OUT" <<'PY' 2>/dev/null
import json,sys
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try:
        d=json.loads(line)
    except Exception:
        continue
    det=d.get("DetectorName","")
    raw=d.get("Raw","")
    meta=d.get("SourceMetadata",{}).get("Data",{}).get("Git",{})
    f=meta.get("file","")
    c=meta.get("commit","")
    print(det,f,c,raw,sep="\t")
PY
)
  fi
  rm -f "$TH_OUT"
else
  row "WARN" "trufflehog" "-" "trufflehog not installed; secret scan incomplete"
  WARNS=$((WARNS+1))
fi

# A push must not be vouched for without an external secret scanner.
if [ "$RANGE_MODE" = "1" ] && ! command -v gitleaks >/dev/null 2>&1 && ! command -v trufflehog >/dev/null 2>&1; then
  row "FAIL" "secret-scanner-missing" "-" "neither gitleaks nor trufflehog installed; refusing to vouch for the range"
  FAILS=$((FAILS+1))
fi

# ---------------------------------------------------------------------------
# 1c. built-in secret regexes (belt-and-braces, catches things scanners miss)
# ---------------------------------------------------------------------------
scan_tree_regex() {
  local target="$1"
  for pat in "${SECRET_PATTERNS[@]}"; do
    while IFS=: read -r file line match; do
      [ -z "$file" ] && continue
      local h; h="$(trimmed_sha256 "$match")"
      if is_allowlisted "$h"; then
        row "ALLOWED" "regex-secret" "$file:$line" "$(mask "$match")"
        ALLOWED=$((ALLOWED+1))
      else
        row "FAIL" "regex-secret" "$file:$line" "$(mask "$match")"
        FAILS=$((FAILS+1))
      fi
    done < <(grep -rInE --binary-files=without-match \
      --exclude-dir=.git -e "$pat" "$target" 2>/dev/null)
  done
}

if [ "$RANGE_MODE" != "1" ]; then
  scan_tree_regex "$REPO"
fi

SENSITIVE_FILE_GLOBS=('.env' '.env.*' '.netrc' '.npmrc' 'id_rsa' 'id_ed25519' '*.pem' '*.key')
if [ "$RANGE_MODE" != "1" ]; then
  for g in "${SENSITIVE_FILE_GLOBS[@]}"; do
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      row "FAIL" "sensitive-file" "$f" "matches pattern $g"
      FAILS=$((FAILS+1))
    done < <(find "$REPO" -not -path '*/.git/*' -iname "$g" 2>/dev/null)
  done
fi

# Blob contents from history/range: regex secrets and denylist terms. Each
# blob is read once; the combined prefilter keeps the common case cheap.
if [ "$HISTORY" = "1" ] || [ "$RANGE_MODE" = "1" ]; then
  BLOB_TXT="$TMPD/blob.txt"
  while read -r blob path; do
    [ -z "$blob" ] && continue
    git -C "$REPO" cat-file -p "$blob" >"$BLOB_TXT" 2>/dev/null || continue
    where="blob:$blob ($path)"

    if grep -qaE -e "$SECRET_ANY" "$BLOB_TXT" 2>/dev/null; then
      for pat in "${SECRET_PATTERNS[@]}"; do
        hitline="$(grep -naE -e "$pat" "$BLOB_TXT" 2>/dev/null | head -1)"
        [ -n "$hitline" ] || continue
        content="${hitline#*:}"
        h="$(trimmed_sha256 "$content")"
        if is_allowlisted "$h"; then
          row "ALLOWED" "regex-secret:history" "$where" "$(mask "$content")"
          ALLOWED=$((ALLOWED+1))
        else
          row "FAIL" "regex-secret:history" "$where" "$(mask "$content")"
          FAILS=$((FAILS+1))
        fi
      done
    fi

    if [ -s "$DENY_SUB" ] || [ -s "$DENY_WORD" ]; then
      if { [ -s "$DENY_SUB" ] && grep -qiF -f "$DENY_SUB" "$BLOB_TXT" 2>/dev/null; } \
        || { [ -s "$DENY_WORD" ] && grep -qiwF -f "$DENY_WORD" "$BLOB_TXT" 2>/dev/null; }; then
        while IFS= read -r term; do
          [ -z "$term" ] && continue
          case "$term" in \#*) continue ;; esac
          if [[ "$term" =~ ^[A-Za-z0-9]+$ ]]; then
            grep -qiwF -e "$term" "$BLOB_TXT" 2>/dev/null || continue
          else
            grep -qiF -e "$term" "$BLOB_TXT" 2>/dev/null || continue
          fi
          row "FAIL" "personal-id:history" "$where" "matched denylist term (masked): $(mask "$term")"
          FAILS=$((FAILS+1))
        done <"$DENYLIST"
      fi
    fi

    # Image blobs get the same metadata check as files on disk.
    case "${path,,}" in
      *.jpg|*.jpeg|*.png|*.heic|*.tiff)
        # exif_check emits its own WARN when neither exiftool nor PIL exists.
        IMG="$TMPD/img.${path##*.}"
        cp "$BLOB_TXT" "$IMG"
        exif_check "$IMG" "$where"
        rm -f "$IMG"
        ;;
    esac
  done <"$BLOB_LIST"
fi

# ---------------------------------------------------------------------------
# 2. personal identifiers (denylist, working tree)
# ---------------------------------------------------------------------------
if [ "$RANGE_MODE" != "1" ] && [ -f "$DENYLIST" ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    case "$term" in \#*) continue;; esac

    # Bare alnum tokens (e.g. a short username) are common substrings of
    # unrelated identifiers (an email local-part, an unrelated project
    # name). Match them on word boundaries; everything else (paths, IPs,
    # domains, MACs) is matched as a plain case-insensitive substring.
    if [[ "$term" =~ ^[A-Za-z0-9]+$ ]]; then
      GREP_OPTS=(-rInEw)
      PATTERN="$term"
    else
      GREP_OPTS=(-rInF)
      PATTERN="$term"
    fi

    while IFS=: read -r file line _; do
      [ -z "$file" ] && continue
      # never flag the denylist source file itself or the audit tooling
      case "$file" in
        */tools/.personal-denylist) continue ;;
      esac
      row "FAIL" "personal-id" "$file:$line" "matched denylist term (masked): $(mask "$term")"
      FAILS=$((FAILS+1))
    done < <(grep "${GREP_OPTS[@]}" --binary-files=without-match --exclude-dir=.git -i "$PATTERN" "$REPO" 2>/dev/null)
  done < "$DENYLIST"
elif [ "$RANGE_MODE" != "1" ]; then
  row "WARN" "personal-denylist" "-" "tools/.personal-denylist not found; personal-ID scan skipped"
  WARNS=$((WARNS+1))
fi

# Push mode: a missing or term-less denylist means the personal-ID scan cannot
# run, so the push is refused rather than vouched for.
if [ "$RANGE_MODE" = "1" ] && { [ ! -f "$DENYLIST" ] || { [ ! -s "$DENY_SUB" ] && [ ! -s "$DENY_WORD" ]; }; }; then
  row "FAIL" "personal-denylist" "-" "tools/.personal-denylist missing or has no terms; push refused (personal-ID scan cannot run)"
  FAILS=$((FAILS+1))
fi

# Range mode: denylist terms in the path names of objects being published.
if [ "$RANGE_MODE" = "1" ] && [ -s "$BLOB_LIST" ]; then
  cut -d' ' -f2- "$BLOB_LIST" >"$TMPD/paths.txt"
  if [ -s "$DENY_SUB" ]; then
    while IFS= read -r hit; do
      row "FAIL" "personal-id:path" "${hit#*:}" "path matches a denylist term"
      FAILS=$((FAILS+1))
    done < <(grep -niF -f "$DENY_SUB" "$TMPD/paths.txt" 2>/dev/null)
  fi
  if [ -s "$DENY_WORD" ]; then
    while IFS= read -r hit; do
      row "FAIL" "personal-id:path" "${hit#*:}" "path matches a denylist term"
      FAILS=$((FAILS+1))
    done < <(grep -niwF -f "$DENY_WORD" "$TMPD/paths.txt" 2>/dev/null)
  fi
fi

# ---------------------------------------------------------------------------
# 3. metadata leaks
# ---------------------------------------------------------------------------
if [ "$RANGE_MODE" != "1" ]; then
  while IFS= read -r img; do
    exif_check "$img" "$img"
  done < <(find "$REPO" -not -path '*/.git/*' -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' -o -iname '*.tiff' \) 2>/dev/null)

  # stray junk that shouldn't ship
  while IFS= read -r f; do
    row "FAIL" "stray-artifact" "$f" "logs/history/state fixture committed to tree"
    FAILS=$((FAILS+1))
  done < <(find "$REPO" -not -path '*/.git/*' -type f \( \
      -iname '*.log' -o -iname '*.jsonl' -o -iname '.bash_history' -o -iname '.zsh_history' \
      -o -path '*/.local/state/*' -o -iname '.psql_history' -o -iname 'shell_history*' \
    \) 2>/dev/null)

  # nested .git dirs (vendored subtree done wrong)
  while IFS= read -r d; do
    [ "$d" = "$REPO/.git" ] && continue
    row "FAIL" "nested-git-dir" "$d" "embedded .git artefact"
    FAILS=$((FAILS+1))
  done < <(find "$REPO" -mindepth 2 -type d -name '.git' 2>/dev/null)
else
  # Range mode: the same file-name rules, applied to the published paths.
  STRAY_GLOBS=('*.log' '*.jsonl' '.bash_history' '.zsh_history' '.psql_history' 'shell_history*')
  shopt -s nocasematch
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    base="${p##*/}"
    for g in "${SENSITIVE_FILE_GLOBS[@]}"; do
      if [[ "$base" == $g ]]; then
        row "FAIL" "sensitive-file" "$p" "matches pattern $g"
        FAILS=$((FAILS+1))
      fi
    done
    for g in "${STRAY_GLOBS[@]}"; do
      if [[ "$base" == $g ]]; then
        row "FAIL" "stray-artifact" "$p" "logs/history/state fixture in published objects"
        FAILS=$((FAILS+1))
      fi
    done
    if [[ "$p" == */.local/state/* || "$p" == .local/state/* ]]; then
      row "FAIL" "stray-artifact" "$p" "logs/history/state fixture in published objects"
      FAILS=$((FAILS+1))
    fi
  done <"$TMPD/paths.txt"
  shopt -u nocasematch
fi

# commit author/committer emails other than the allowed one; Co-Authored-By lines
ALLOWED_EMAIL="mapasenul@gmail.com"
if [ "$HISTORY" = "1" ] || [ "$RANGE_MODE" = "1" ]; then
  while IFS=$'\t' read -r commit email; do
    [ -z "$commit" ] && continue
    if [ "$email" != "$ALLOWED_EMAIL" ]; then
      row "WARN" "commit-author-email" "commit:$commit" "author/committer email is $email (expected $ALLOWED_EMAIL)"
      WARNS=$((WARNS+1))
    fi
  done < <(git -C "$REPO" log "${AUDIT_ARGS[@]}" --format='%H%x09%ae%n%H%x09%ce' 2>/dev/null | sort -u)

  while IFS= read -r line; do
    row "WARN" "co-authored-by" "$line" "Co-Authored-By / AI attribution line in commit message"
    WARNS=$((WARNS+1))
  done < <(git -C "$REPO" log "${AUDIT_ARGS[@]}" --format='%H %s%n%b' 2>/dev/null | grep -inE 'co-authored-by|generated with|claude code' | cut -c1-140)
fi

# email visibility note (always, not just history)
row "WARN" "public-email" "-" "author email $ALLOWED_EMAIL will be public in commit metadata once pushed; consider GitHub noreply rewrite if that's undesired"
WARNS=$((WARNS+1))

# ---------------------------------------------------------------------------
# 4. installer / attack-surface hygiene (WARN only, working tree)
# ---------------------------------------------------------------------------
warn_pattern() {
  local pat="$1" label="$2"
  while IFS=: read -r file line match; do
    [ -z "$file" ] && continue
    row "WARN" "$label" "$file:$line" "$(echo "$match" | cut -c1-100)"
    WARNS=$((WARNS+1))
  done < <(grep -rInE --binary-files=without-match --exclude-dir=.git -e "$pat" "$REPO" 2>/dev/null)
}
if [ "$RANGE_MODE" != "1" ]; then
  warn_pattern 'curl[^|]*\|[[:space:]]*(sh|bash)' 'curl-pipe-shell'
  warn_pattern 'wget[^|]*\|[[:space:]]*(sh|bash)' 'wget-pipe-shell'
  warn_pattern '\bsudo\b' 'sudo-usage'
  warn_pattern 'chmod[[:space:]]+777' 'chmod-777'
  warn_pattern '\beval[[:space:]]*\(' 'eval-usage'
  warn_pattern '\bcurl\b.*-o[[:space:]]' 'unpinned-download'
  warn_pattern 'git verify-tag|verify-commit' 'signature-verify-present'

  # telemetry / outbound hosts (informational, always WARN not FAIL)
  while IFS=: read -r file line match; do
    [ -z "$file" ] && continue
    row "WARN" "network-call" "$file:$line" "$(echo "$match" | cut -c1-100)"
    WARNS=$((WARNS+1))
  done < <(grep -rInE --binary-files=without-match --exclude-dir=.git \
    'https?://[a-zA-Z0-9.-]+' "$REPO" 2>/dev/null | grep -viE '\.git/|schema\.org|w3\.org|github\.com/[^/]+/[^/]+$' | head -200)
fi

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------
echo
printf '%-6s | %-24s | %-40s | %s\n' "SEV" "CHECK" "LOCATION" "DETAIL"
printf -- '-%.0s' {1..120}; echo
if [ "${#ROWS[@]}" -eq 0 ]; then
  echo "(no findings)"
else
  for r in "${ROWS[@]}"; do
    IFS='|' read -r sev check loc detail <<< "$r"
    printf '%-6s | %-24s | %-40s | %s\n' "$sev" "$check" "$loc" "$detail"
  done
fi
echo
echo "Summary: $FAILS FAIL, $WARNS WARN, $ALLOWED ALLOWED"

if [ "$FAILS" -gt 0 ]; then
  exit 1
fi
exit 0
