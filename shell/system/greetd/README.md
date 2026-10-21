# qml-rice greetd greeter

Since 6 Oct 2026 the greeter shows `lock/GlassLockSurface.qml` (the
liquid-glass login: frosted clock, glass password pill that grows from a
circle, status orb) over the owner's current wallpaper, which `install.sh`
copies to `/usr/share/qml-rice-greeter/media/` (read as the target user,
never as root). If the glass surface fails to load, the greeter falls back
to the ASCII surface described below, and `greeter-launch.sh` still falls
back to the old greeter if nothing draws within 20s.

## Previous: ASCII greeter

Renders the exact lock/AsciiLockSurface.qml lock screen as the greetd
greeter (single user, configurable at install time; no picker), via a state
machine (`GreetdContext.qml`) driving `Quickshell.Services.Greetd` instead of
PAM directly. niri still hosts it (reuses `/etc/greetd/quickshell-greeter/
niri-greeter.kdl` unmodified).

## Files

- `greeter.qml` — production entry, loads AsciiLockSurface via an absolute
  `file://` Loader (quickshell's `-p` sandbox blocks relative `../..`
  imports — see its header), writes a readiness marker after first frame.
- `GreetdContext.qml` — real greetd state machine. No test path.
- `FakeGreetdContext.qml` / `greeter-test.qml` — dev-only test double + IPC
  test harness (`QMLRICE_GREETER_TEST=1`). **Never installed.**
- `greeter-launch.sh` — greetd's actual `command`; waits for the readiness
  marker (20s), falls back to the untouched old greeter on timeout/crash,
  and gives up on the new greeter for the rest of the boot after 2 fallbacks.
- `install.sh` — run with `sudo bash install.sh`. Idempotent.

## Install / rollback

    sudo bash <repo>/shell/system/greetd/install.sh [user]
    sudo cp /etc/greetd/config.toml.bak-<timestamp> /etc/greetd/config.toml
