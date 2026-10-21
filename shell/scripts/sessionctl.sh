#!/usr/bin/env bash
set -euo pipefail

action=${1:-}

available_command() {
    command -v "$1" >/dev/null 2>&1
}

login1_capability() {
    local method=$1 result value
    if ! available_command busctl; then
        printf 'missing\n'
        return
    fi
    result=$(busctl --system call org.freedesktop.login1 \
        /org/freedesktop/login1 org.freedesktop.login1.Manager \
        "$method" 2>/dev/null || true)
    value=${result#*\"}
    value=${value%%\"*}
    if [[ $value == yes || $value == challenge ]]; then
        printf 'ready\n'
    else
        printf 'missing\n'
    fi
}

# "Shut down" hibernates by default so every app (terminals included) comes
# back exactly as left. Returns 0 when a REAL poweroff is required instead.
#
# Available facts:
#   uname -r                          running kernel, e.g. 7.2.3-arch1-3
#   /usr/lib/modules/<version>/       gone after pacman replaced that kernel,
#                                     and a new kernel will refuse the image
#   login1_capability CanHibernate    prints ready|missing
#   /sys/class/power_supply/BAT0/capacity   battery percent
must_really_power_off() {
    # Kernel was upgraded since boot: the new kernel would discard the image
    # and the "restored" session would silently be a cold boot anyway.
    [[ -d /usr/lib/modules/$(uname -r) ]] || return 0
    # Hibernation unavailable (swap gone, lockdown, etc.): don't fail silently.
    [[ $(login1_capability CanHibernate) == ready ]] || return 0
    return 1
}

case $action in
    probe)
        available_command loginctl && printf 'LOCK=ready\n' || printf 'LOCK=missing\n'
        available_command hyprctl && printf 'LOGOUT=ready\n' || printf 'LOGOUT=missing\n'
        printf 'SUSPEND=%s\n' "$(login1_capability CanSuspend)"
        printf 'HIBERNATE=%s\n' "$(login1_capability CanHibernate)"
        printf 'REBOOT=%s\n' "$(login1_capability CanReboot)"
        printf 'SHUTDOWN=%s\n' "$(login1_capability CanPowerOff)"
        ;;
    lock)
        # The session's own lock screen (whatever the user has configured --
        # hyprlock, swaylock, or none) owns what happens next. This shell only
        # asks logind to lock the session; it does not launch or configure a
        # locker itself.
        available_command loginctl || exit 69
        exec loginctl lock-session
        ;;
    suspend)
        available_command systemctl || exit 69
        exec systemctl suspend
        ;;
    hibernate)
        available_command systemctl || exit 69
        exec systemctl hibernate
        ;;
    logout)
        available_command hyprctl || exit 69
        # This Hyprland build uses the Lua configuration API. Execute its
        # native exit dispatcher directly instead of relying on legacy syntax.
        exec hyprctl eval 'hl.dispatch(hl.dsp.exit())'
        ;;
    reboot)
        available_command systemctl || exit 69
        exec systemctl reboot
        ;;
    shutdown)
        available_command systemctl || exit 69
        must_really_power_off && exec systemctl poweroff
        exec systemctl hibernate
        ;;
    *)
        printf 'invalid session action\n' >&2
        exit 64
        ;;
esac
