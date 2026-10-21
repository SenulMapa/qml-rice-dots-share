#!/usr/bin/env bash
# Transaction boundary for Odyssey's private awww renderer namespace.
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
# Persisted wallpaper state lives under XDG_STATE_HOME if set, else the
# standard $HOME/.local/state fallback.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/odyssey"
runtime_root="${XDG_RUNTIME_DIR:-/tmp}/odyssey"
current_file="$state_dir/current-wallpaper"
manifest_file="$state_dir/wallpaper-manifest.json"
sddm_wallpaper_file="${ODYSSEY_SDDM_WALLPAPER_EXPORT:-/var/tmp/odyssey-sddm-current-wallpaper}"
recovery_file="$state_dir/awww-recovery-attempts"
candidate_dir="$runtime_root/wallpaper-candidate"
active_palette="${ODYSSEY_ACTIVE_PALETTE:-$state_dir/palette.json}"
palette_generator="${ODYSSEY_PALETTE_GENERATOR:-$project_dir/scripts/generate-palette.sh}"
namespace=odyssey
frame_cache="${XDG_CACHE_HOME:-$HOME/.cache}/qml-rice/wallpaper-frames"
video_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/qml-rice/wallpaper-video"
mpvpaper_pid_file="$runtime_root/mpvpaper.pids"
mpvpaper_video_file="$runtime_root/mpvpaper.video"
# gSlapper (preferred video backend when installed): pid files, IPC sockets and
# per-output pause markers live next to mpvpaper's. mpvpaper stays as fallback.
# `fill` is gSlapper's crop-to-cover mode (mpv's panscan=1.0); gSlapper's own
# panscan=1.0 would letterbox instead.
gslapper_opts="no-audio loop fill"
transcode_pid_file="$runtime_root/transcode.pid"
transcode_status_file="$runtime_root/transcode.status"
transcode_target_file="$runtime_root/transcode.target"
encoder_cache_file="$state_dir/video-encoder-cache"
video_max_fps="${ODYSSEY_WALLPAPER_MAX_FPS:-30}"
# Proxy quality (cq/qp/crf). It was 23 under a 6M cap, which smeared moving
# water and foliage into blocks: SSIM 0.923 vs the lanczos-downscaled
# source, against 0.966 at 18 under a 25M cap. A 1080p30 loop at ~25 Mbps is
# still trivial for hwdec, even on the UHD 620. It is part of the cache key,
# so changing it re-encodes instead of serving a stale proxy.
proxy_cq="${ODYSSEY_WALLPAPER_PROXY_CQ:-18}"
# Lean playback profile for the UHD 620 target: safe hwdec fallback, no
# interpolation/deband/high-order scaling work, a small demuxer buffer
# (proxies are already small, and looping means nothing to read ahead far),
# and video-sync=desync so mpv paces frames off the clip's own timestamps
# instead of the display's refresh rate -- the dev box's 120/240Hz panels
# would otherwise force needless extra frame duplication work.
# load-scripts=no keeps /etc/mpv/scripts/mpris.so out of THIS instance: the
# wallpaper is not music, but mpris.so exported it on the session bus as a
# player called "mpv", so the shell's media card, hover pill and OSD all
# latched onto the looping wallpaper file instead of whatever is actually
# playing. Wallpaper playback needs no mpv scripts at all.
mpv_opts="load-scripts=no no-audio loop-file=inf hwdec=auto-safe profile=fast framedrop=vo interpolation=no deband=no scale=bilinear cscale=bilinear dscale=bilinear video-sync=desync vd-lavc-threads=2 cache=no demuxer-max-bytes=16MiB panscan=1.0 --really-quiet"
recovery_window=60
recovery_limit=3
probe_count="${ODYSSEY_AWWW_PROBE_COUNT:-10}"
probe_delay="${ODYSSEY_AWWW_PROBE_DELAY:-0.2}"
verify_delay="${ODYSSEY_AWWW_VERIFY_DELAY:-}"
backoff_base="${ODYSSEY_AWWW_BACKOFF_BASE:-0.2}"

mkdir -p "$state_dir" "$runtime_root" "$video_cache_dir"
chmod 700 "$runtime_root" 2>/dev/null || true

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
valid_image() { [[ -f $1 && ${1,,} =~ \.(png|jpe?g|webp|gif|mp4|webm|mkv|mov)$ ]]; }
is_video() { [[ -f $1 && ${1,,} =~ \.(mp4|webm|mkv|mov)$ ]]; }
canonical() { realpath -e -- "$1" 2>/dev/null; }
query() { awww query --namespace "$namespace" --json; }
ready() { query >/dev/null 2>&1; }
conflict() { pgrep -x hyprpaper >/dev/null 2>&1; }

extract_video_frame() {
    local video=$1 frame_file mtime hash
    [[ -f $video ]] || return 1
    command -v ffmpeg >/dev/null || return 1
    mtime=$(stat -c '%Y' -- "$video" 2>/dev/null) || return 1
    hash=$(printf '%s\n' "$video:$mtime" | sha256sum | awk '{print $1}' | cut -c1-16)
    mkdir -p "$frame_cache"
    frame_file="$frame_cache/$hash.png"
    if [[ -f $frame_file ]]; then
        printf '%s\n' "$frame_file"
        return 0
    fi
    if ffmpeg -y -loglevel error -i "$video" -ss 1 -frames:v 1 "$frame_file" 2>/dev/null \
        || ffmpeg -y -loglevel error -i "$video" -frames:v 1 "$frame_file" 2>/dev/null; then
        printf '%s\n' "$frame_file"
        return 0
    fi
    rm -f "$frame_file"
    return 1
}

images() {
    # awww 0.12 groups outputs by namespace. Fixtures use the direct array form.
    query | jq -c '
        (if type == "object" then [.[] | .[]?] else . end)
        | [.[] | {
            name: (.name // .output // ""),
            image: (.displaying.image // .image // .path // "")
        }]
        | map(select(.name != ""))
    '
}

requested_outputs_exist() {
    local snapshot=$1 names=$2
    jq -e --arg names "$names" '
        . as $rows | ($names | split(",") | map(select(length > 0))) as $wanted
        | ($wanted | length) > 0
        and all($wanted[]; . as $name | any($rows[]; .name == $name))
    ' <<<"$snapshot" >/dev/null
}

verify_assignments() {
    local expected=$1 actual
    actual=$(images) || return 1
    jq -e --argjson actual "$actual" '
        . as $expected
        | all($expected[]; . as $want
            | any($actual[]; .name == $want.name and .image == $want.image))
    ' <<<"$expected" >/dev/null
}

select_assignments() {
    local snapshot=$1 names=$2
    jq -c --arg names "$names" '
        ($names | split(",") | map(select(length > 0))) as $wanted
        | [.[] | select(.name as $name | any($wanted[]; . == $name))]
    ' <<<"$snapshot"
}

render_assignments() {
    local assignments=$1 image names result=0
    while IFS= read -r image; do
        [[ -n $image ]] || continue
        names=$(jq -r --arg image "$image" '
            [.[] | select(.image == $image) | .name] | join(",")
        ' <<<"$assignments")
        [[ -n $names ]] || continue
        if ! valid_image "$image"; then
            printf 'committed wallpaper is unavailable: %s\n' "$image" >&2
            result=1
            continue
        fi
        awww img --namespace "$namespace" --outputs "$names" \
            --transition-type none "$image" || result=1
    done < <(jq -r '.[].image' <<<"$assignments" | sort -u)
    return "$result"
}

restore_snapshot() {
    local snapshot=$1 names=${2:-} expected
    expected=$snapshot
    if [[ -n $names ]]; then
        expected=$(select_assignments "$snapshot" "$names")
    fi
    render_assignments "$expected" || return 1
    verify_assignments "$expected"
}

effect_args() {
    local effect=$1 duration=$2 reduced=$3 fps=${4:-60}
    if [[ $reduced == true ]]; then
        printf '%s\0' --transition-type none
        return
    fi
    # Frame rate follows the TARGET display. awww defaults to 30 fps, which on a
    # 120 Hz panel reads as a stutter next to a shell animating at panel rate;
    # 60 Hz laptops still get 60, which keeps it light on integrated graphics.
    printf '%s\0' --transition-duration "$duration" --transition-fps "$fps"
    case $effect in
        fade) printf '%s\0' --transition-type fade ;;
        slide) printf '%s\0' --transition-type left ;;
        wipe) printf '%s\0' --transition-type wipe --transition-angle 45 ;;
        # Ricelin's wave: a broad, shallow 60,30 wave at 30 degrees. Its script sets no
        # duration, so it inherits awww's 3 s default -- the slowness is the feel.
        wave) printf '%s\0' --transition-type wave --transition-angle 30 --transition-wave 60,30 ;;
        # 'expand' is impasto's "Circle": awww's 'center' is itself an alias
        # for a growing circle centred on the screen (`awww img --help`), so
        # this is already the same transition impasto ships under that name.
        expand) printf '%s\0' --transition-type center ;;
        # 'contract' is impasto's "Outer": the same growing-circle transition
        # run in reverse (shrinking rather than growing).
        contract) printf '%s\0' --transition-type outer ;;
        spotlight) printf '%s\0' --transition-type any ;;
        # impasto's "None": instant, no transition at all. Distinct from the
        # `reduced == true` branch above (which also forces this) so a user
        # can pick it explicitly via Config.wallpaper.transition regardless
        # of the reduced-motion setting.
        none) printf '%s\0' --transition-type none ;;
        random) printf '%s\0' --transition-type random ;;
        # awww's own vocabulary, added for the impasto settings port's
        # WallpaperTransitionPreview tiles: "grow" is awww's real growing-
        # circle transition (impasto's own name for it is "circle"); "outer"
        # is the same call "contract" above already makes (kept as its own
        # case so the impasto tile's value round-trips as "outer" rather than
        # silently renaming itself to "contract"); "none" is an instant cut.
        grow) printf '%s\0' --transition-type grow ;;
        outer) printf '%s\0' --transition-type outer ;;
        none) printf '%s\0' --transition-type none ;;
        *) die 'unsupported transition' ;;
    esac
}

clamp_duration() {
    awk -v d="$1" 'BEGIN {
        if (d !~ /^[0-9]+([.][0-9]+)?$/) d=.9
        d=(d<.3?.3:(d>4?4:d)); printf "%.1f", int(d*10+.5)/10
    }'
}

prune_recovery_attempts() {
    local now cutoff temp
    now=$(date +%s)
    cutoff=$((now - recovery_window))
    temp=$(mktemp "$state_dir/.recovery.XXXXXX")
    if [[ -f $recovery_file ]]; then
        awk -v cutoff="$cutoff" '$1 ~ /^[0-9]+$/ && $1 >= cutoff' \
            "$recovery_file" >"$temp"
    fi
    chmod 600 "$temp"
    mv -f "$temp" "$recovery_file"
}

start_renderer() {
    local mode=${1:-auto} attempts attempt poll backoff
    command -v awww >/dev/null && command -v awww-daemon >/dev/null \
        || { say STATE=missing; return 1; }
    if ready; then
        say STATE=ready
        return 0
    fi
    if conflict; then
        say STATE=conflict
        return 2
    fi
    if [[ $mode == probe ]]; then
        say STATE=unavailable
        return 1
    fi
    if [[ $mode == manual ]]; then
        : >"$recovery_file"
        chmod 600 "$recovery_file"
    fi
    prune_recovery_attempts
    attempts=$(wc -l <"$recovery_file")
    if [[ $mode != manual && $attempts -ge $recovery_limit ]]; then
        say STATE=exhausted
        return 1
    fi
    attempt=$((attempts + 1))
    date +%s >>"$recovery_file"
    say STATE=recovering
    say "ATTEMPT=$attempt"
    if [[ $backoff_base != 0 && $attempt -gt 1 ]]; then
        backoff=$(awk -v base="$backoff_base" -v attempt="$attempt" \
            'BEGIN { printf "%.2f", base * (2 ^ (attempt - 2)) }')
        sleep "$backoff"
    fi
    (XDG_CACHE_HOME="$runtime_root/cache" awww-daemon --namespace "$namespace" \
        --no-cache --quiet >/dev/null 2>&1 &)
    poll=0
    while (( poll < probe_count )); do
        sleep "$probe_delay"
        if ready; then
            say STATE=ready
            return 0
        fi
        ((poll += 1))
    done
    prune_recovery_attempts
    attempts=$(wc -l <"$recovery_file")
    if [[ $mode != manual && $attempts -ge $recovery_limit ]]; then
        say STATE=exhausted
    else
        say STATE=unavailable
    fi
    return 1
}

reconcile_manifest() {
    local live committed fallback desired image
    [[ -f $manifest_file ]] || return 0
    jq -e '.version == 2 and (.wallpaper | type == "string")
        and (.scheme | type == "string") and (.assignments | type == "array")' \
        "$manifest_file" >/dev/null || return 1
    live=$(images) || return 1
    committed=$(jq -c '.assignments' "$manifest_file")
    fallback=$(jq -r '.wallpaper' "$manifest_file")
    valid_image "$fallback" || return 1
    desired=$(jq -cn --argjson live "$live" --argjson committed "$committed" \
        --arg fallback "$fallback" '
        [$live[] | .name as $name
            | {name: $name,
               image: (([$committed[] | select(.name == $name) | .image][0])
                   // $fallback)}]
    ')
    while IFS= read -r image; do
        [[ -z $image ]] || valid_image "$image" || return 1
    done < <(jq -r '.[].image' <<<"$desired" | sort -u)
    render_assignments "$desired" || return 1
    verify_assignments "$desired"
}

candidate_matches() {
    local image=$1 scheme=$2 token=$3
    [[ -f $candidate_dir/manifest.json && -f $candidate_dir/palette.json ]] \
        || return 1
    jq -e --arg image "$image" --arg scheme "$scheme" --arg token "$token" '
        .image == $image and .scheme == $scheme and .token == $token
    ' "$candidate_dir/manifest.json" >/dev/null
}

restore_file() {
    local backup=$1 destination=$2 existed=$3
    if [[ $existed == true ]]; then
        cp -f -- "$backup" "$destination"
        chmod 600 "$destination"
    else
        rm -f -- "$destination"
    fi
}

publish_sddm_wallpaper() {
    local image=$1 parent base temporary owner
    [[ $sddm_wallpaper_file == /* && $sddm_wallpaper_file != / ]] \
        || return 1
    parent=${sddm_wallpaper_file%/*}
    base=${sddm_wallpaper_file##*/}
    [[ -n $parent && -n $base && -d $parent && ! -L $parent ]] || return 1
    if [[ -e $sddm_wallpaper_file || -L $sddm_wallpaper_file ]]; then
        [[ -f $sddm_wallpaper_file && ! -L $sddm_wallpaper_file ]] || return 1
        owner=$(stat -c '%u' -- "$sddm_wallpaper_file") || return 1
        [[ $owner == $UID ]] || return 1
    fi
    temporary=$(mktemp "$parent/.${base}.XXXXXX") || return 1
    if ! install -m 0644 -- "$image" "$temporary" \
            || ! mv -f -- "$temporary" "$sddm_wallpaper_file"; then
        rm -f -- "$temporary"
        return 1
    fi
}

restore_sddm_wallpaper() {
    local backup=$1 existed=$2
    if [[ $existed == true ]]; then
        install -m 0644 -- "$backup" "$sddm_wallpaper_file"
    else
        rm -f -- "$sddm_wallpaper_file"
    fi
}

wait_for_pid_exit() {
    # Poll a PID that is NOT a child of this shell (mpvpaper/transcode
    # workers survive across separate script invocations) -- `wait` on a
    # non-child pid is a silent no-op, so this is the only correct way to
    # block for exit.
    local pid=$1 timeout_tenths=$2 waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < timeout_tenths )); do
        sleep 0.1
        ((waited += 1))
    done
    ! kill -0 "$pid" 2>/dev/null
}

start_mpvpaper_output() {
    local out=$1 video=$2 pid_file="$runtime_root/mpvpaper-$out.pid"
    [[ -f $video ]] || return 1
    command -v mpvpaper >/dev/null || return 1
    # Idempotent: if pid is already running for this output, skip
    if [[ -f $pid_file ]]; then
        local pid=$(<"$pid_file")
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # Already running
        fi
    fi
    # mpvpaper's own auto-pause (-p) additionally pauses decode when the
    # background layer surface itself isn't visible (e.g. workspace
    # switched away entirely).
    nohup mpvpaper -p -o "$mpv_opts" "$out" "$video" \
        >/dev/null 2>&1 & local pid=$!; disown
    printf '%s\n' "$pid" >"$pid_file"
}

stop_mpvpaper_output() {
    local out=$1 pid_file="$runtime_root/mpvpaper-$out.pid"
    if [[ -f $pid_file ]]; then
        local pid=$(<"$pid_file")
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait_for_pid_exit "$pid" 40 || {
                kill -9 "$pid" 2>/dev/null || true
                wait_for_pid_exit "$pid" 20 || true
            }
        fi
        rm -f "$pid_file"
    fi
}

mpvpaper_running_pid() {
    local pid
    # Check if any output pid file has a live process
    for pid_file in "$runtime_root"/mpvpaper-*.pid; do
        [[ -f $pid_file ]] || continue
        local pid=$(<"$pid_file")
        [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && {
            printf '%s\n' "$pid"
            return 0
        }
    done
    return 1
}

stop_mpvpaper() {
    # Stop all output processes
    for pid_file in "$runtime_root"/mpvpaper-*.pid; do
        [[ -f $pid_file ]] || continue
        local out=${pid_file##*mpvpaper-}
        out=${out%.pid}
        stop_mpvpaper_output "$out"
    done
    rm -f "$mpvpaper_video_file"
    # Fallback: the shell is the sole owner of mpvpaper, so this is safe.
    # Covers strays left behind by a crashed prior shell instance.
    if pgrep -x mpvpaper >/dev/null 2>&1; then
        pkill -x mpvpaper 2>/dev/null || true
        local waited=0
        while pgrep -x mpvpaper >/dev/null 2>&1 && (( waited < 20 )); do
            sleep 0.1
            ((waited += 1))
        done
        pgrep -x mpvpaper >/dev/null 2>&1 && pkill -9 -x mpvpaper 2>/dev/null || true
    fi
}

start_mpvpaper() {
    local video=$1 out out_list
    [[ -f $video ]] || return 1
    command -v mpvpaper >/dev/null || return 1
    # Idempotent: if the exact same source is already playing everywhere, return 0
    if [[ -f $mpvpaper_video_file ]]; then
        local running_video=$(<"$mpvpaper_video_file")
        if [[ $running_video == "$video" ]] && mpvpaper_running_pid >/dev/null; then
            return 0
        fi
    fi
    # Stop all existing processes before starting new ones
    stop_mpvpaper
    # Write the current video file
    printf '%s\n' "$video" >"$mpvpaper_video_file"
    # Start mpvpaper on each connected output
    out_list=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null) || out_list=""
    if [[ -z $out_list ]]; then
        # Fallback: single wallpaper on '*' if monitor list is empty
        nohup mpvpaper -p -o "$mpv_opts" '*' "$video" >/dev/null 2>&1 & local pid=$!; disown
        printf '%s\n' "$pid" >"$runtime_root/mpvpaper-wildcard.pid"
    else
        while IFS= read -r out; do
            [[ -z $out ]] && continue
            start_mpvpaper_output "$out" "$video"
        done <<<"$out_list"
    fi
}

# Swap the playing clip without disturbing per-output pause state: only outputs
# with a live mpvpaper get restarted. Paused outputs have no pid file (pausing
# stops them), and resume reads $mpvpaper_video_file, so they pick the new clip
# up then instead of decoding behind a fullscreen game now.
swap_mpvpaper_video() {
    local video=$1 pid_file out pid
    [[ -f $video ]] || return 1
    [[ -f $mpvpaper_video_file && $(<"$mpvpaper_video_file") == "$video" ]] && return 0
    printf '%s\n' "$video" >"$mpvpaper_video_file"
    for pid_file in "$runtime_root"/mpvpaper-*.pid; do
        [[ -f $pid_file ]] || continue
        out=${pid_file##*mpvpaper-}
        out=${out%.pid}
        pid=$(<"$pid_file")
        [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || continue
        stop_mpvpaper_output "$out"
        if [[ $out == wildcard ]]; then
            nohup mpvpaper -p -o "$mpv_opts" '*' "$video" >/dev/null 2>&1 & pid=$!; disown
            printf '%s\n' "$pid" >"$pid_file"
        else
            start_mpvpaper_output "$out" "$video"
        fi
    done
}

# ---- gSlapper backend ------------------------------------------------------
# One gslapper process with output '*' decodes ONE pipeline and renders it on
# every output (confirmed in src/main.c: a single global GstElement pipeline,
# '*' matches all outputs in output_done). Every output here always shows the
# same clip, so a single '*' process is used (tag "wildcard"). Pause/resume go
# through its IPC socket, so a "paused" process keeps its VRAM; only
# stop-video frees it.
use_gslapper() { command -v gslapper >/dev/null; }
video_backend_available() { use_gslapper || command -v mpvpaper >/dev/null; }

gslapper_ipc() {
    local sock=$1 reply
    [[ -S $sock ]] || return 1
    command -v socat >/dev/null || return 1
    reply=$(printf '%s\n' "$2" | socat -t0.5 - "UNIX-CONNECT:$sock" 2>/dev/null) || return 1
    [[ $reply == OK* ]]
}

gslapper_wait_socket() {
    local sock=$1 waited=0
    while [[ ! -S $sock ]] && (( waited < 30 )); do
        sleep 0.1
        ((waited += 1))
    done
    [[ -S $sock ]]
}

start_gslapper_target() {
    local tag=$1 target=$2 video=$3 pid
    local pid_file="$runtime_root/gslapper-$tag.pid" sock="$runtime_root/gslapper-$tag.sock"
    [[ -f $video ]] || return 1
    use_gslapper || return 1
    if [[ -f $pid_file ]]; then
        pid=$(<"$pid_file")
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # Already running
        fi
    fi
    # No -p: gslapper 1.5.2's auto-pause stops rendering, so it never gets the
    # frame callback that would resume it; a 2 s gap at login froze the video
    # for the whole session. The shell's own pause markers cover the real cases.
    # 30fps cap and no saved state (the shell owns what plays, not gslapper's
    # restore file).
    nohup gslapper --fps-cap 30 --no-save-state -I "$sock" \
        -o "$gslapper_opts" "$target" "$video" >/dev/null 2>&1 & pid=$!; disown
    printf '%s\n' "$pid" >"$pid_file"
}

stop_gslapper_target() {
    local tag=$1 pid
    local pid_file="$runtime_root/gslapper-$tag.pid"
    if [[ -f $pid_file ]]; then
        pid=$(<"$pid_file")
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait_for_pid_exit "$pid" 40 || {
                kill -9 "$pid" 2>/dev/null || true
                wait_for_pid_exit "$pid" 20 || true
            }
        fi
        rm -f "$pid_file"
    fi
    rm -f "$runtime_root/gslapper-$tag.sock"
}

gslapper_running_pid() {
    local pid_file pid
    for pid_file in "$runtime_root"/gslapper-*.pid; do
        [[ -f $pid_file ]] || continue
        pid=$(<"$pid_file")
        [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && {
            printf '%s\n' "$pid"
            return 0
        }
    done
    return 1
}

stop_gslapper() {
    local pid_file tag
    for pid_file in "$runtime_root"/gslapper-*.pid; do
        [[ -f $pid_file ]] || continue
        tag=${pid_file##*gslapper-}
        stop_gslapper_target "${tag%.pid}"
    done
    rm -f "$runtime_root"/gslapper-paused-*
    # Same sole-owner assumption as stop_mpvpaper: sweep strays from a crashed
    # prior shell instance.
    if pgrep -x gslapper >/dev/null 2>&1; then
        pkill -x gslapper 2>/dev/null || true
        local waited=0
        while pgrep -x gslapper >/dev/null 2>&1 && (( waited < 20 )); do
            sleep 0.1
            ((waited += 1))
        done
        pgrep -x gslapper >/dev/null 2>&1 && pkill -9 -x gslapper 2>/dev/null || true
    fi
}

start_gslapper() {
    local video=$1
    [[ -f $video ]] || return 1
    use_gslapper || return 1
    if [[ -f $mpvpaper_video_file ]]; then
        local running_video
        running_video=$(<"$mpvpaper_video_file")
        if [[ $running_video == "$video" ]] && gslapper_running_pid >/dev/null; then
            return 0
        fi
    fi
    stop_video
    printf '%s\n' "$video" >"$mpvpaper_video_file"
    start_gslapper_target wildcard '*' "$video"
}

# Pause state per output is a marker file (gslapper-paused-<out>). The shared
# '*' pipeline pauses only when EVERY connected output is marked paused;
# a per-output process pauses on its own marker.
apply_gslapper_pause_state() {
    local pid_file tag sock out all_paused monitors rc=0 cmd
    monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null) || monitors=""
    for pid_file in "$runtime_root"/gslapper-*.pid; do
        [[ -f $pid_file ]] || continue
        tag=${pid_file##*gslapper-}
        tag=${tag%.pid}
        sock="$runtime_root/gslapper-$tag.sock"
        if [[ $tag == wildcard ]]; then
            all_paused=true
            [[ -n $monitors ]] || all_paused=false
            while IFS= read -r out; do
                [[ -z $out ]] && continue
                [[ -f $runtime_root/gslapper-paused-$out ]] || all_paused=false
            done <<<"$monitors"
            [[ -f $runtime_root/gslapper-paused-wildcard ]] && all_paused=true
        elif [[ -f $runtime_root/gslapper-paused-$tag ]]; then
            all_paused=true
        else
            all_paused=false
        fi
        cmd=resume
        [[ $all_paused == true ]] && cmd=pause
        gslapper_ipc "$sock" "$cmd" || rc=1
    done
    return $rc
}

handle_set_video_pause_gslapper() {
    local pair out state
    while [[ $# -gt 0 ]]; do
        pair=$1
        shift
        out=${pair%%=*}
        state=${pair#*=}
        if [[ $state == 1 ]]; then
            : >"$runtime_root/gslapper-paused-$out"
        elif [[ $state == 0 ]]; then
            rm -f "$runtime_root/gslapper-paused-$out"
            # Any output resuming means "every output paused" is no longer
            # true, so a stale wildcard marker must not keep the shared
            # pipeline paused (it froze the video after every unlock).
            rm -f "$runtime_root/gslapper-paused-wildcard"
        fi
    done
    gslapper_running_pid >/dev/null || return 1
    apply_gslapper_pause_state
}

# Restart the running gslapper with a new clip (day/night swap), then re-assert
# the pause state, since a fresh process always starts playing.
swap_gslapper_video() {
    local video=$1 pid_file tag pid
    [[ -f $video ]] || return 1
    [[ -f $mpvpaper_video_file && $(<"$mpvpaper_video_file") == "$video" ]] && return 0
    printf '%s\n' "$video" >"$mpvpaper_video_file"
    for pid_file in "$runtime_root"/gslapper-*.pid; do
        [[ -f $pid_file ]] || continue
        tag=${pid_file##*gslapper-}
        tag=${tag%.pid}
        pid=$(<"$pid_file")
        [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || continue
        stop_gslapper_target "$tag"
        if [[ $tag == wildcard ]]; then
            start_gslapper_target wildcard '*' "$video"
        else
            start_gslapper_target "$tag" "$tag" "$video"
        fi
        gslapper_wait_socket "$runtime_root/gslapper-$tag.sock" || true
    done
    apply_gslapper_pause_state || true
}

# Backend dispatchers: gslapper when installed, mpvpaper otherwise. Stopping
# always clears both so a backend switch never leaves a stray player behind.
start_video() {
    if use_gslapper; then start_gslapper "$1"; else start_mpvpaper "$1"; fi
}

stop_video() {
    stop_gslapper
    stop_mpvpaper
}

swap_video() {
    if use_gslapper; then swap_gslapper_video "$1"; else swap_mpvpaper_video "$1"; fi
}

# Day/night variants. A video with a sibling "<stem>.night.<ext>" plays that
# clip at night. Only playback switches: the committed wallpaper, its still
# frame and the palette all stay keyed to the day file.
night_variant() {
    local stem=${1%.*} ext=${1##*.}
    [[ -f $stem.night.$ext ]] && printf '%s\n' "$stem.night.$ext"
}

is_night() {
    # TODO(owner): decide what "night" means -- return 0 when it is.
    return 1
}

playing_variant() {
    local night
    if is_night && night=$(night_variant "$1"); then
        printf '%s\n' "$night"
    else
        printf '%s\n' "$1"
    fi
}

handle_set_video_pause() {
    local pair out state video=""
    if use_gslapper; then
        # IPC pause/resume: the process stays resident, no signals or respawns.
        if handle_set_video_pause_gslapper "$@"; then
            for pair in "$@"; do say "PAUSE_OK=${pair%%=*}"; done
        else
            for pair in "$@"; do say "PAUSE_FAIL=${pair%%=*}"; done
        fi
        return 0
    fi
    # Only a resume needs the current video; a stop must work even without it.
    [[ -f $mpvpaper_video_file ]] && video=$(<"$mpvpaper_video_file")
    while [[ $# -gt 0 ]]; do
        pair=$1
        shift
        out=${pair%%=*}
        state=${pair#*=}
        if [[ $state == 1 ]]; then
            # Stop: remove the process
            if stop_mpvpaper_output "$out"; then
                say "PAUSE_OK=$out"
            else
                say "PAUSE_FAIL=$out"
            fi
        elif [[ $state == 0 ]]; then
            # Start: resume the process
            if [[ -n $video ]] && start_mpvpaper_output "$out" "$video"; then
                say "PAUSE_OK=$out"
            else
                say "PAUSE_FAIL=$out"
            fi
        fi
    done
}

cancel_transcode() {
    local pid
    if [[ -f $transcode_pid_file ]]; then
        pid=$(<"$transcode_pid_file")
        if [[ $pid =~ ^[0-9]+$ ]]; then
            # Launched via setsid, so the pid is also its process group id --
            # kill the whole group so the ffmpeg child dies with the worker.
            kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$transcode_pid_file" "$transcode_target_file" "$transcode_status_file"
}

target_resolution() {
    local out
    out=$(hyprctl monitors -j 2>/dev/null | jq -r '
        [.[] | select((.disabled // false) | not)
            | {w: (((.width // 1920) / (.scale // 1)) | floor),
               h: (((.height // 1080) / (.scale // 1)) | floor)}]
        | if length == 0 then empty else (max_by(.w * .h) | "\(.w)x\(.h)") end
    ' 2>/dev/null)
    [[ $out =~ ^[0-9]+x[0-9]+$ ]] && printf '%s\n' "$out" || printf '1920x1080\n'
}

video_stream_info() {
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,avg_frame_rate,codec_name \
        -of json -- "$1" 2>/dev/null
}

video_fps() {
    local info=$1 fps_raw num den
    fps_raw=$(jq -r '.streams[0].avg_frame_rate // "30/1"' <<<"$info")
    num=${fps_raw%/*}; den=${fps_raw#*/}
    [[ -z $den || $den == 0 ]] && den=1
    [[ -z $num ]] && num=30
    awk -v n="$num" -v d="$den" 'BEGIN { v = n / d; if (v <= 0) v = 30; printf "%.3f", v }'
}

# Returns success (0) when the source already fits the target box, is
# already at/under the fps cap, and is already in a codec the target GPU
# decodes natively -- i.e. transcoding would be pure waste.
video_needs_transcode() {
    local src=$1 tw=$2 th=$3 mfps=$4 info sw sh codec fps
    info=$(video_stream_info "$src") || return 0
    [[ -n $info ]] || return 0
    sw=$(jq -r '.streams[0].width // 0' <<<"$info")
    sh=$(jq -r '.streams[0].height // 0' <<<"$info")
    codec=$(jq -r '.streams[0].codec_name // ""' <<<"$info")
    fps=$(video_fps "$info")
    case $codec in h264|hevc|vp9) ;; *) return 0 ;; esac
    [[ $sw =~ ^[0-9]+$ && $sw -gt 0 && $sw -le $tw ]] || return 0
    [[ $sh =~ ^[0-9]+$ && $sh -gt 0 && $sh -le $th ]] || return 0
    awk -v f="$fps" -v m="$mfps" 'BEGIN { exit !(f <= m + 0.01) }' || return 0
    return 1
}

proxy_cache_path() {
    local src=$1 key=$2 mtime hash
    mtime=$(stat -c '%Y' -- "$src" 2>/dev/null) || mtime=0
    hash=$(printf '%s' "$src:$mtime:$key" | sha256sum | awk '{print $1}')
    printf '%s/%s.mp4\n' "$video_cache_dir" "$hash"
}

# Probes h264_nvenc, then h264_vaapi (against every /dev/dri/renderD* node),
# then falls back to libx264. Result is cached to disk as "<encoder>|<extra>"
# so every apply after the first skips the (cheap but non-zero) probe cost.
probe_encoder() {
    if [[ -f $encoder_cache_file ]]; then
        cat "$encoder_cache_file"
        return 0
    fi
    local result="" node
    # 256x144, not a tiny 64x64: measured on the dev RTX 5060, h264_nvenc
    # rejects anything under ~144px on a side ("Frame Dimension less than
    # the minimum supported value") -- a too-small probe frame would always
    # report nvenc as unusable even when it works fine on real video sizes.
    if command -v ffmpeg >/dev/null && ffmpeg -y -loglevel error -f lavfi \
            -i "testsrc=size=256x144:rate=5:duration=1" -frames:v 5 \
            -c:v h264_nvenc -f null - >/dev/null 2>&1; then
        result="h264_nvenc|"
    fi
    if [[ -z $result ]]; then
        for node in /dev/dri/renderD*; do
            [[ -e $node ]] || continue
            if ffmpeg -y -loglevel error -hwaccel vaapi -hwaccel_device "$node" \
                    -f lavfi -i "testsrc=size=256x144:rate=5:duration=1" -frames:v 5 \
                    -vf format=nv12,hwupload -c:v h264_vaapi -f null - \
                    >/dev/null 2>&1; then
                result="h264_vaapi|$node"
                break
            fi
        done
    fi
    [[ -z $result ]] && result="libx264|"
    printf '%s\n' "$result" >"$encoder_cache_file"
    printf '%s\n' "$result"
}

run_transcode() {
    # Detached background worker: run_transcode <src> <out> <target-res> <max-fps>
    local src=$1 out=$2 target=$3 maxfps=$4
    local tw=${target%x*} th=${target#*x}
    local encoder_line encoder extra info fps outfps gop scale_expr tmp_out
    mkdir -p "$video_cache_dir"
    printf 'STAGE=probing\n' >"$transcode_status_file"
    encoder_line=$(probe_encoder)
    encoder=${encoder_line%%|*}
    extra=${encoder_line#*|}
    info=$(video_stream_info "$src")
    fps=$(video_fps "$info")
    outfps=$(awk -v s="$fps" -v m="$maxfps" 'BEGIN { print (s < m ? s : m) }')
    gop=$(awk -v f="$outfps" 'BEGIN { g = int(f * 2 + 0.5); print (g < 1 ? 48 : g) }')
    # lanczos, not swscale's bicubic default: these proxies are mostly 4K
    # sources supersampled to 1080p, and the sharper kernel keeps that detail.
    scale_expr="scale='min(iw,${tw})':'min(ih,${th})':force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos"
    tmp_out="$out.part"
    printf 'STAGE=encoding\n' >"$transcode_status_file"
    if ! encode_with "$encoder" "$extra" "$src" "$tmp_out" "$scale_expr" "$outfps" "$gop"; then
        rm -f "$tmp_out"
        # A probe pass succeeding doesn't guarantee the real job does too
        # (driver hiccup, VRAM pressure); fall back to software once rather
        # than leaving the wallpaper stuck on the still frame forever.
        if [[ $encoder != libx264 ]] \
                && encode_with libx264 "" "$src" "$tmp_out" "$scale_expr" "$outfps" "$gop"; then
            rm -f "$encoder_cache_file"
        else
            rm -f "$tmp_out"
            printf 'STAGE=failed\n' >"$transcode_status_file"
            return 1
        fi
    fi
    mv -f "$tmp_out" "$out"
    printf 'STAGE=done\nPROXY=%s\n' "$out" >"$transcode_status_file"
}

encode_with() {
    local encoder=$1 extra=$2 src=$3 out=$4 scale_expr=$5 outfps=$6 gop=$7
    case $encoder in
        h264_nvenc)
            # -f mp4 is forced rather than left to extension-sniffing: $out is
            # a "$proxy.part" staging path (see run_transcode) so ffmpeg can't
            # infer the container from its name.
            ffmpeg -y -loglevel error -i "$src" \
                -vf "$scale_expr" -r "$outfps" -an \
                -c:v h264_nvenc -preset p7 -tune hq -profile:v high -pix_fmt yuv420p \
                -rc vbr -cq "$proxy_cq" -b:v 0 -maxrate 25M -bufsize 50M -spatial-aq 1 \
                -g "$gop" -keyint_min "$gop" -movflags +faststart -f mp4 "$out"
            ;;
        h264_vaapi)
            ffmpeg -y -loglevel error -hwaccel vaapi -hwaccel_device "$extra" \
                -i "$src" -vf "${scale_expr},format=nv12,hwupload" -r "$outfps" -an \
                -c:v h264_vaapi -profile:v high -qp "$proxy_cq" -maxrate 25M -bufsize 50M \
                -g "$gop" -keyint_min "$gop" -movflags +faststart -f mp4 "$out"
            ;;
        *)
            ffmpeg -y -loglevel error -i "$src" \
                -vf "$scale_expr" -r "$outfps" -an \
                -c:v libx264 -preset faster -profile:v high -pix_fmt yuv420p \
                -crf "$proxy_cq" -maxrate 25M -bufsize 50M -g "$gop" -keyint_min "$gop" \
                -sc_threshold 0 -movflags +faststart -f mp4 "$out"
            ;;
    esac
}

# Orchestrates the whole video path: reuse a cached proxy, play the source
# directly when it's already light enough, or kick off a background
# transcode (cancelling any stale one for a different source first) and
# leave the still frame on screen until it lands.
ensure_video_playing() {
    local video starter=${2:-start_video} target proxy current_target pid
    video=$(playing_variant "$1")
    video_backend_available || return 1
    target=$(target_resolution)
    proxy=$(proxy_cache_path "$video" "${target}|${video_max_fps}|q${proxy_cq}")

    if [[ -f $transcode_target_file ]]; then
        current_target=$(<"$transcode_target_file")
        [[ $current_target == "$video" ]] || cancel_transcode
    fi

    if [[ -f $proxy ]]; then
        "$starter" "$proxy"
        say "MPVPAPER=started"
        return 0
    fi

    if ! video_needs_transcode "$video" "${target%x*}" "${target#*x}" "$video_max_fps"; then
        "$starter" "$video"
        say "MPVPAPER=started"
        return 0
    fi

    if [[ -f $transcode_pid_file && -f $transcode_target_file ]] \
            && [[ $(<"$transcode_target_file") == "$video" ]]; then
        pid=$(<"$transcode_pid_file")
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            say "TRANSCODE=running"
            return 0
        fi
    fi

    : >"$transcode_status_file"
    printf '%s\n' "$video" >"$transcode_target_file"
    setsid "$0" _transcode-worker "$video" "$proxy" "$target" "$video_max_fps" \
        >/dev/null 2>&1 & local pid=$!; disown
    printf '%s\n' "$pid" >"$transcode_pid_file"
    say "TRANSCODE=started"
}

report_current() {
    local wp=$1 still
    say "CURRENT=$wp"
    if is_video "$wp"; then
        still=$(extract_video_frame "$wp" 2>/dev/null) || still=""
    else
        still=$wp
    fi
    [[ -n $still ]] && say "STILL=$still"
}

publish_commit() {
    local image=$1 assignments=$2 scheme=$3 transaction is_video_flag
    local palette_existed=false manifest_existed=false current_existed=false sddm_existed=false
    transaction=$(mktemp -d "$runtime_root/.wallpaper-publish.XXXXXX")
    trap 'rm -rf "$transaction"' RETURN
    if is_video "$image"; then
        is_video_flag=true
    else
        is_video_flag=false
    fi
    if [[ -f $active_palette ]]; then
        cp -f -- "$active_palette" "$transaction/palette.before"
        palette_existed=true
    fi
    if [[ -f $manifest_file ]]; then
        cp -f -- "$manifest_file" "$transaction/manifest.before"
        manifest_existed=true
    fi
    if [[ -f $current_file ]]; then
        cp -f -- "$current_file" "$transaction/current.before"
        current_existed=true
    fi
    if [[ -e $sddm_wallpaper_file || -L $sddm_wallpaper_file ]]; then
        [[ -f $sddm_wallpaper_file && ! -L $sddm_wallpaper_file ]] || return 1
        cp -f -- "$sddm_wallpaper_file" "$transaction/sddm.before"
        sddm_existed=true
    fi
    install -m 600 "$candidate_dir/palette.json" "$transaction/palette.next"
    jq -n --arg wallpaper "$image" --arg scheme "$scheme" \
        --argjson assignments "$assignments" --arg isVideo "$is_video_flag" \
        '{version:2,wallpaper:$wallpaper,scheme:$scheme,isVideo:($isVideo=="true"),assignments:$assignments}' \
        >"$transaction/manifest.next"
    printf '%s\n' "$image" >"$transaction/current.next"
    chmod 600 "$transaction/manifest.next" "$transaction/current.next"
    if [[ ${ODYSSEY_FAIL_PUBLICATION:-false} == true ]]; then
        return 1
    fi
    if ! publish_sddm_wallpaper "$image" \
        || ! install -m 600 "$transaction/palette.next" "$active_palette" \
        || ! install -m 600 "$transaction/manifest.next" "$manifest_file" \
        || ! install -m 600 "$transaction/current.next" "$current_file"; then
        restore_file "$transaction/palette.before" "$active_palette" "$palette_existed" || true
        restore_file "$transaction/manifest.before" "$manifest_file" "$manifest_existed" || true
        restore_file "$transaction/current.before" "$current_file" "$current_existed" || true
        restore_sddm_wallpaper "$transaction/sddm.before" "$sddm_existed" || true
        return 1
    fi
    rm -rf "$transaction"
    trap - RETURN
}

case ${1:-} in
    list)
        shift
        roots=()
        for root in "$@"; do [[ -d $root ]] && roots+=("$root"); done
        ((${#roots[@]})) && find "${roots[@]}" -maxdepth 3 -type f \
            \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' \
                -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) \
            ! -iname '*.night.*' -print 2>/dev/null | sort -u
        ;;
    probe)
        start_renderer probe || true
        [[ -f $current_file ]] && report_current "$(<"$current_file")"
        true
        ;;
    bootstrap)
        mode=${2:-auto}
        if start_renderer "$mode"; then
            if reconcile_manifest; then
                say RECONCILED=true
                if [[ -f $current_file ]]; then
                    current_wp=$(<"$current_file")
                    report_current "$current_wp"
                    if is_video "$current_wp"; then
                        ensure_video_playing "$current_wp"
                    fi
                fi
                true
            else
                say RECONCILED=false
                die 'committed wallpaper reconciliation failed'
            fi
        else
            exit 1
        fi
        ;;
    candidate)
        image=$(canonical "$2") || die 'wallpaper does not exist'
        valid_image "$image" || die 'unsupported wallpaper format'
        scheme=$3
        token=$4
        rm -rf "$candidate_dir"
        mkdir -p "$candidate_dir"
        chmod 700 "$candidate_dir"
        # For videos, extract first frame for palette generation
        palette_input=$image
        if is_video "$image"; then
            palette_input=$(extract_video_frame "$image") \
                || die 'failed to extract video frame for palette generation'
        fi
        "$palette_generator" "$palette_input" "$scheme" \
            "$candidate_dir/palette.json" >/dev/null
        jq -n --arg image "$image" --arg scheme "$scheme" --arg token "$token" \
            '{image:$image,scheme:$scheme,token:$token}' \
            >"$candidate_dir/manifest.json"
        chmod 600 "$candidate_dir"/*.json
        say "CANDIDATE=$candidate_dir"
        ;;
    cancel-candidate)
        rm -rf "$candidate_dir"
        if [[ -f $transcode_target_file ]]; then
            committed=""
            [[ -f $current_file ]] && committed=$(<"$current_file")
            [[ $(<"$transcode_target_file") == "$committed" ]] || cancel_transcode
        fi
        say CANCELLED=true
        ;;
    cancel-transcode)
        cancel_transcode
        say CANCELLED=true
        ;;
    stop-video)
        stop_video
        cancel_transcode
        say STOPPED=true
        ;;
    frame)
        image=$(canonical "$2") || die 'wallpaper does not exist'
        if is_video "$image"; then
            extract_video_frame "$image" || die 'frame extraction failed'
        else
            printf '%s\n' "$image"
        fi
        ;;
    transcode-status)
        if [[ -f $transcode_status_file ]]; then
            cat "$transcode_status_file"
        else
            say STAGE=idle
        fi
        [[ -f $transcode_target_file ]] && say "TARGET=$(<"$transcode_target_file")"
        ;;
    start-video)
        video=$(canonical "$2") || die 'wallpaper does not exist'
        is_video "$video" || die 'not a video'
        start_video "$video" || die 'video backend unavailable'
        say "MPVPAPER=started"
        ;;
    pause-video)
        # Deprecated: mapped to set-video-pause for all outputs at =1
        out_list=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null) || out_list=""
        if [[ -z $out_list ]]; then
            handle_set_video_pause "wildcard=1"
        else
            args=()
            while IFS= read -r out; do
                [[ -n $out ]] && args+=("$out=1")
            done <<<"$out_list"
            handle_set_video_pause "${args[@]}"
        fi
        ;;
    resume-video)
        # Deprecated: mapped to set-video-pause for all outputs at =0
        out_list=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null) || out_list=""
        if [[ -z $out_list ]]; then
            handle_set_video_pause "wildcard=0"
        else
            args=()
            while IFS= read -r out; do
                [[ -n $out ]] && args+=("$out=0")
            done <<<"$out_list"
            handle_set_video_pause "${args[@]}"
        fi
        ;;
    set-video-pause)
        shift
        handle_set_video_pause "$@"
        ;;
    _transcode-worker)
        run_transcode "$2" "$3" "$4" "$5"
        ;;
    apply)
        image=$(canonical "$2") || die 'wallpaper does not exist'
        valid_image "$image" || die 'unsupported wallpaper format'
        scheme=$3
        target=$4
        names=$5
        effect=$6
        seconds=$(clamp_duration "$7")
        reduced=${8:-false}
        token=${9:-}
        [[ $target == current || $target == all ]] || die 'invalid output target'
        candidate_matches "$image" "$scheme" "$token" || die 'stale candidate'
        start_renderer auto >/dev/null || die 'renderer unavailable'
        [[ -n $names ]] || die 'no live outputs'

        # For videos, use extracted frame for awww, then start mpvpaper
        apply_image=$image
        if is_video "$image"; then
            apply_image=$(extract_video_frame "$image") \
                || die 'failed to extract video frame for display'
        else
            # Stop mpvpaper (and any in-flight transcode) if transitioning
            # from video to still/gif.
            stop_video
            cancel_transcode
        fi

        before=$(images) || die 'renderer query failed'
        requested_outputs_exist "$before" "$names" || die 'requested output unavailable'
        expected=$(jq -c --arg image "$apply_image" --arg names "$names" '
            ($names | split(",") | map(select(length > 0))) as $wanted
            | [.[] | if (.name as $name | any($wanted[]; . == $name))
                then .image = $image else . end]
        ' <<<"$before")
        fps=$(hyprctl monitors -j 2>/dev/null | jq -r --arg names "$names" '
            ($names | split(",")) as $wanted
            | [.[] | select(.name as $n | any($wanted[]; . == $n)) | .refreshRate]
            | (max // 60) | if . < 30 then 60 else (. + 0.5 | floor) end' 2>/dev/null)
        [[ $fps =~ ^[0-9]+$ ]] || fps=60
        mapfile -d '' args < <(effect_args "$effect" "$seconds" "$reduced" "$fps")
        if ! awww img --namespace "$namespace" --outputs "$names" \
                "${args[@]}" "$apply_image"; then
            restore_snapshot "$before" "$names" || true
            die 'renderer apply failed; previous assignments restored'
        fi
        delay=${verify_delay:-$(awk -v d="$seconds" 'BEGIN { printf "%.1f", d + .2 }')}
        [[ $delay == 0 ]] || sleep "$delay"
        if ! verify_assignments "$(select_assignments "$expected" "$names")"; then
            restore_snapshot "$before" "$names" || true
            die 'renderer verification failed; previous assignments restored'
        fi
        after=$(images) || {
            restore_snapshot "$before" "$names" || true
            die 'renderer query failed; previous assignments restored'
        }
        if ! publish_commit "$image" "$after" "$scheme"; then
            restore_snapshot "$before" "$names" || true
            die 'palette publication failed; previous assignments restored'
        fi

        # Videos: reuse/build the optimised proxy and play that, not the
        # raw source (see ensure_video_playing).
        if is_video "$image"; then
            ensure_video_playing "$image" || say "MPVPAPER=unavailable"
        fi

        rm -rf "$candidate_dir"
        report_current "$image"
        say PALETTE=updated
        say COMMITTED=true
        ;;
    scheme)
        image=$(canonical "$2") || die 'wallpaper does not exist'
        scheme=$3
        token=$4
        candidate_matches "$image" "$scheme" "$token" || die 'stale candidate'
        start_renderer auto >/dev/null || die 'renderer unavailable'
        reconcile_manifest || die 'renderer reconciliation failed'
        assignments=$(images) || die 'renderer query failed'
        publish_commit "$image" "$assignments" "$scheme" \
            || die 'palette publication failed'
        rm -rf "$candidate_dir"
        report_current "$image"
        say PALETTE=updated
        say COMMITTED=true

        # A scheme change never touches the video content itself, so
        # ensure_video_playing's idempotency check makes this a no-op if the
        # same proxy (or source) is already running -- no gratuitous restart.
        if is_video "$image"; then
            ensure_video_playing "$image" || true
        fi
        ;;
    tick)
        # Day/night re-resolution for the shell's slow timer. Idempotent: a
        # no-op unless the variant flipped, and it never resumes a paused
        # output. A variant without a proxy yet starts its transcode here and
        # is swapped in by the next tick.
        if [[ -f $current_file ]]; then
            current_wp=$(<"$current_file")
            if is_video "$current_wp"; then
                ensure_video_playing "$current_wp" swap_video || true
            fi
        fi
        true
        ;;
    reconcile)
        start_renderer auto >/dev/null || exit 1
        reconcile_manifest || die 'committed wallpaper reconciliation failed'
        if [[ -f $current_file ]]; then
            current_wp=$(<"$current_file")
            if is_video "$current_wp"; then
                ensure_video_playing "$current_wp" || true
            fi
        fi
        say RECONCILED=true
        ;;
    *)
        printf 'usage: %s {list|probe|bootstrap|candidate|cancel-candidate|apply|scheme|reconcile|tick|frame|start-video|stop-video|pause-video|resume-video|set-video-pause|transcode-status|cancel-transcode}\n' \
            "$0" >&2
        exit 2
        ;;
esac
