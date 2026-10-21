#!/usr/bin/env bash
# Layer 6 self-test. Exit 0 = pass. Never touches the live desktop: every
# apply/revert/toggle run uses a throwaway HOME, and hyprctl/brave are stubs.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/webapps.json"
FAILS=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
need() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL  missing tool: $1"; exit 1; }; }
need jq; need luac; need desktop-file-validate; need lua5.4

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- 1. static: syntax of every committed file --------------------------
for s in "$HERE/gen.sh" "$HERE/apply.sh" "$HERE/revert.sh" "$HERE/check.sh"; do
    bash -n "$s" && pass "bash -n $(basename "$s")" || fail "bash -n $(basename "$s")"
done
jq -e 'type == "array" and length > 0' "$MANIFEST" >/dev/null && pass "manifest is a non-empty array" || fail "manifest"
for f in "$REPO/hypr/hyprland.lua" "$REPO/hypr/hyprland/webapps.lua"; do
    luac -p "$f" && pass "luac -p $(basename "$f")" || fail "luac -p $f"
done
for f in "$REPO"/dots/webapps/.local/bin/webapp-*; do
    bash -n "$f" && pass "bash -n $(basename "$f")" || fail "bash -n $f"
done
for f in "$REPO"/dots/webapps/.local/share/applications/webapp-*.desktop; do
    desktop-file-validate "$f" && pass "desktop-file-validate $(basename "$f")" || fail "desktop-file-validate $f"
done

# ---- 2. generated files match the manifest (gen.sh is deterministic) ----
GEN="$WORK/gen"
bash "$HERE/gen.sh" "$GEN" >/dev/null && pass "gen.sh runs" || fail "gen.sh failed"
if diff -r "$GEN/dots/webapps" "$REPO/dots/webapps" >/dev/null && cmp -s "$GEN/hypr/hyprland/webapps.lua" "$REPO/hypr/hyprland/webapps.lua"; then
    pass "committed generated files == gen.sh output"
else
    fail "committed generated files stale; run tools/mac-webapps/gen.sh"
fi
# No stray generated files beyond the manifest's ids.
expected=0
while IFS= read -r id; do
    for f in "$REPO/dots/webapps/.local/bin/webapp-$id" "$REPO/dots/webapps/.local/bin/webapp-$id-toggle" \
             "$REPO/dots/webapps/.local/share/applications/webapp-$id.desktop"; do
        [ -f "$f" ] && expected=$((expected + 1))
    done
done < <(jq -r '.[].id' "$MANIFEST")
actual="$(find "$REPO/dots/webapps" -type f | wc -l)"
[ "$expected" -eq "$actual" ] && pass "$actual generated files, all from manifest" || fail "stray files in dots/webapps ($actual vs $expected)"

# Keys: well-formed, unique, and not already bound anywhere in the repo.
keys_ok=1
KEY_RE='^(SUPER|CTRL|ALT|SHIFT)( \+ (SUPER|CTRL|ALT|SHIFT))* \+ [A-Za-z0-9]+$'
while IFS= read -r key; do
    if ! [[ "$key" =~ $KEY_RE ]]; then
        fail "key '$key' is not in 'MOD + KEY' form"; keys_ok=0; continue
    fi
    hits="$(grep -rlF -- "\"$key\"" "$REPO/hypr" "$REPO/install.sh" 2>/dev/null | grep -v 'hypr/hyprland/webapps.lua' || true)"
    if [ -n "$hits" ]; then fail "key '$key' already bound in: $hits"; keys_ok=0; fi
done < <(jq -r '.[].key' "$MANIFEST")
[ "$keys_ok" -eq 1 ] && pass "bind keys well-formed and free in repo"
dupes="$(jq -r '.[].key' "$MANIFEST" | sort | uniq -d)"
[ -z "$dupes" ] && pass "bind keys unique" || fail "duplicate keys: $dupes"

# ---- 3. Lua rules load and produce the expected calls (stub hl API) -----
LUA_STUB="$WORK/hl_stub.lua"
cat > "$LUA_STUB" <<'LUA'
calls = { rules = {}, binds = {} }
hl = {
  window_rule = function(t) calls.rules[#calls.rules + 1] = t end,
  bind = function(k, f, o) calls.binds[#calls.binds + 1] = { key = k, opts = o, fn = f } end,
  dsp = { exec_cmd = function(c) return { exec = c } end },
}
HOME = os.getenv("HOME")
dofile(os.getenv("WEBAPPS_LUA"))
assert(#calls.rules == 4 * tonumber(os.getenv("APP_COUNT")), "rule count " .. #calls.rules)
assert(#calls.binds == tonumber(os.getenv("APP_COUNT")), "bind count " .. #calls.binds)
for _, b in ipairs(calls.binds) do
  assert(b.fn.exec:find("/.local/bin/webapp-.*-toggle$"), "bind exec " .. b.fn.exec)
end
print("lua-rules " .. #calls.rules .. " rules, " .. #calls.binds .. " binds")
LUA
APP_COUNT="$(jq 'length' "$MANIFEST")"
if env WEBAPPS_LUA="$REPO/hypr/hyprland/webapps.lua" APP_COUNT="$APP_COUNT" HOME=/nonexistent \
    lua5.4 "$LUA_STUB" >"$WORK/lua.out" 2>&1; then
    pass "webapps.lua evaluates: $(cat "$WORK/lua.out")"
else
    fail "webapps.lua evaluation: $(cat "$WORK/lua.out")"
fi

# ---- 4. apply -> apply (idempotent) -> revert (exact) in a throwaway HOME ----
H="$WORK/home"
mkdir -p "$H/.config/hypr"
cp "$REPO/hypr/hyprland.lua" "$H/.config/hypr/hyprland.lua"
# Tree digest. ./.local/state is kept on purpose (backups), so it is excluded, and so is
# the ./.local dir entry itself, which only survives because state/ lives under it.
snap() { (cd "$1" && find . -path ./.local/state -prune -o \( -type f -o -type l \) -print0 | sort -z | xargs -0 sha256sum 2>/dev/null; find . -path ./.local/state -prune -o -type d ! -path . ! -path ./.local -print | sort); }
snap "$H" > "$WORK/before.txt"

export HOME="$H"
bash "$HERE/apply.sh" >"$WORK/apply1.log" 2>&1 && pass "apply.sh first run" || { fail "apply.sh first run"; cat "$WORK/apply1.log"; }
snap "$H" > "$WORK/after1.txt"
bash "$HERE/apply.sh" >"$WORK/apply2.log" 2>&1 && pass "apply.sh second run" || fail "apply.sh second run"
snap "$H" > "$WORK/after2.txt"
if diff -q "$WORK/after1.txt" "$WORK/after2.txt" >/dev/null && grep -q "already applied" "$WORK/apply2.log"; then
    pass "apply.sh is idempotent"
else
    fail "apply.sh not idempotent"
fi
req_count="$(grep -c 'require("hyprland.webapps")' "$H/.config/hypr/hyprland.lua")"
[ "$req_count" -eq 1 ] && pass "exactly one webapps require line in live-copy hyprland.lua" || fail "require count $req_count"
glass_line="$(grep -n 'require("hyprland.glass")' "$H/.config/hypr/hyprland.lua" | cut -d: -f1)"
web_line="$(grep -n 'require("hyprland.webapps")' "$H/.config/hypr/hyprland.lua" | cut -d: -f1)"
[ "$web_line" -gt "$glass_line" ] && pass "webapps require sits after the glass blur" || fail "require order"
while IFS= read -r id; do
    for f in "$H/.local/bin/webapp-$id" "$H/.local/bin/webapp-$id-toggle"; do
        [ -x "$f" ] && pass "installed executable $(basename "$f")" || fail "not executable: $f"
    done
    [ -f "$H/.local/share/applications/webapp-$id.desktop" ] && pass "installed desktop webapp-$id" || fail "desktop webapp-$id missing"
done < <(jq -r '.[].id' "$MANIFEST")
[ -f "$H/.config/hypr/hyprland/webapps.lua" ] && pass "installed webapps.lua" || fail "webapps.lua missing"

# Toggle behaviour with stubbed hyprctl and brave (the window appears when brave runs).
STUBS="$WORK/stubs"; mkdir -p "$STUBS"
STUB_STATE="$WORK/stub-state"; mkdir -p "$STUB_STATE"
cat > "$STUBS/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
  clients) cat "$STUB_STATE/clients.json" ;;
  dispatch) echo "$*" >> "$STUB_STATE/dispatch.log" ;;
esac
SH
cat > "$STUBS/brave" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_STATE/brave.log"
printf '[{"class":"webapp-gemini"}]' > "$STUB_STATE/clients.json"
SH
chmod +x "$STUBS/hyprctl" "$STUBS/brave"
export STUB_STATE
run_toggle() { PATH="$STUBS:$PATH" timeout 15 "$H/.local/bin/webapp-gemini-toggle" >/dev/null 2>&1; }
reset_state() { rm -f "$STUB_STATE"/brave.log "$STUB_STATE"/dispatch.log; printf '%s' "$1" > "$STUB_STATE/clients.json"; }

reset_state '[]'
run_toggle
if [ -f "$STUB_STATE/brave.log" ] && grep -q -- '--app=https://gemini.google.com/app' "$STUB_STATE/brave.log" \
   && grep -q -- '--class=webapp-gemini' "$STUB_STATE/brave.log" \
   && grep -q -- "--user-data-dir=$H/.local/share/qml-rice/webapps/gemini" "$STUB_STATE/brave.log" \
   && [ "$(wc -l < "$STUB_STATE/dispatch.log")" -eq 1 ] && grep -q 'toggle_special("webapp-gemini")' "$STUB_STATE/dispatch.log"; then
    pass "toggle with no window: launches brave app-mode then reveals special"
else
    fail "toggle with no window"
fi

for cls in '[{"class":"webapp-gemini"}]' '[{"class":"brave-gemini.google.com__app-Default"}]'; do
    reset_state "$cls"
    run_toggle
    if [ ! -f "$STUB_STATE/brave.log" ] && [ "$(wc -l < "$STUB_STATE/dispatch.log")" -eq 1 ]; then
        pass "toggle with existing window $cls: no relaunch, one toggle"
    else
        fail "toggle with existing window $cls"
    fi
done
reset_state '[{"class":"brave-browser"},{"class":"kitty"}]'
run_toggle
[ -f "$STUB_STATE/brave.log" ] && pass "unrelated windows do not count as the web app" || fail "unrelated windows matched"
# The launcher's profile dir is a runtime artifact of the toggle, not of apply.
rm -rf "$H/.local/share/qml-rice"

export HOME="$H"
bash "$HERE/revert.sh" >"$WORK/revert.log" 2>&1 && pass "revert.sh runs" || { fail "revert.sh"; cat "$WORK/revert.log"; }
snap "$H" > "$WORK/reverted.txt"
if diff -q "$WORK/before.txt" "$WORK/reverted.txt" >/dev/null; then
    pass "revert restores the exact original tree"
else
    fail "revert left differences: $(diff "$WORK/before.txt" "$WORK/reverted.txt" | head -5)"
fi

if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$FAILS FAILURE(S)"; exit 1
