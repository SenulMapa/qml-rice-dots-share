# odyssey

odyssey is a Quickshell desktop shell for Hyprland built around a contextual system surface. It brings everyday controls, information, and workflows into one focused interface.

> Minimal when idle. Informational when needed. Powerful when requested. Intelligent when useful.

> [!NOTE]
> odyssey is currently a **public alpha**. Core functionality is usable today, but features, appearance, configuration, and installation behavior may continue to evolve.

## Your system, your configuration

odyssey is designed to integrate with your system, not take ownership of it.

You remain free to manage your own Hyprland configuration, shell, applications, packages, and system setup. odyssey provides the configuration and integration required for its desktop experience, while keeping user-owned configuration and system management in your control.

The installer supports preserving existing configuration, and files that odyssey needs to modify or replace are backed up before changes are made.

odyssey should be something you can build your setup around — not something that prevents you from making the setup your own.

## Highlights

### A contextual system surface

odyssey's Dynamic Island stays compact at rest and expands contextually as you interact with the system.

It provides access to notifications, media, workspaces, device status, system controls, and focused OSD feedback for volume, microphone, brightness, and power changes without permanently occupying additional screen space.

<img width="1280" height="720" alt="overview" src="https://github.com/user-attachments/assets/4e345f7e-493a-454d-a7df-b100ffbcaf7d" />

### Dashboard and insights

The expanded Dashboard brings together time, weather, calendar, recent notifications, media, quick controls, and system information in one view.

Weather is unconfigured by default. Set your location under **Settings → Dashboard** to enable current conditions and forecasts.

<img width="1280" height="720" alt="insight1" src="https://github.com/user-attachments/assets/0e6b67c2-d6c9-476f-97b5-847cc4a05296" />

### Launcher and command palette

Search and launch applications, switch Hyprland workspaces, or execute odyssey actions from a keyboard-friendly launcher and command palette.

<img width="1280" height="720" alt="launcher" src="https://github.com/user-attachments/assets/471655d0-56fb-40ec-a13d-6db0b48d460d" />

### Control Center

Manage common desktop controls without leaving the shell, including:

- volume and microphone
- display brightness
- Wi-Fi and network information
- Bluetooth
- battery status
- power profiles
- do-not-disturb

<img width="1280" height="720" alt="control" src="https://github.com/user-attachments/assets/6eee267d-a357-4bcb-a387-5c6f3982df56" />

### Notifications and media

odyssey provides its own notification service with contextual previews and notification history.

Active media is integrated directly into the island and Dashboard, providing playback information and controls without requiring a separate widget or panel.

<img width="1280" height="720" alt="notify" src="https://github.com/user-attachments/assets/5f120182-01d5-4802-85c0-7b34e173f7d2" />

### Wallpapers and adaptive theming

Browse and apply wallpapers per monitor directly from odyssey.

odyssey uses **Matugen** to generate an adaptive color palette from your wallpaper and propagate it throughout the shell and supported desktop integrations for a cohesive appearance.

<img width="1280" height="720" alt="wallpaper" src="https://github.com/user-attachments/assets/2647efb7-75a2-4f13-9135-6187a74872f9" />

## Features

odyssey currently includes:

- contextual Dynamic Island and system OSDs
- application launcher and command palette
- Hyprland workspace integration
- Dashboard and system insights
- notification service and notification history
- media playback controls
- Wi-Fi and network controls
- Bluetooth controls
- audio and microphone controls
- brightness and power controls
- weather and forecasts
- calendar views
- wallpaper management
- Matugen-powered adaptive theming
- system monitoring
- configurable odyssey settings
- stable IPC commands for scripting and custom keybindings

## Installation

odyssey currently targets **Arch Linux with Hyprland and Quickshell**.

Clone the repository and run the guided installer:

```bash
git clone https://github.com/sud0-L/odyssey.git
cd odyssey
./install.sh
```

The installer is deliberately minimal and reversible. It writes fonts, a
`qml-rice` launcher command, and its own keybind file
(`~/.config/hypr/qml-rice-binds.lua`), plus one `pcall(require, ...)` line
appended to `hyprland.lua`. It does not replace your Hyprland config, theme
your terminal, or touch hypridle/hyprlock. Everything it touches is backed up
first and listed by `./uninstall.sh`.

## IPC and custom keybindings

odyssey exposes a stable IPC interface for shell actions.

For example:

```bash
qml-rice ipc launcher toggle
qml-rice ipc control-center toggle
qml-rice ipc audio increment 3
qml-rice ipc audio decrement 3
qml-rice ipc audio mute
qml-rice ipc audio micmute
```

These commands can be used from Hyprland keybindings, scripts, or other desktop integrations.

## Things to know

### Notifications

odyssey provides its own freedesktop notification service. Running another notification daemon at the same time may cause conflicts.

### Configuration backups

The installer backs up `hyprland.lua` next to itself (as
`hyprland.lua.bak-qml-rice-<timestamp>`) before appending its one
`pcall(require, ...)` line. Nothing else in your configuration is touched.

### Weather

Weather is intentionally unconfigured on a fresh installation. Configure your location from **Settings → Dashboard** after odyssey is running.

## Requirements

- Arch Linux
- Hyprland
- Quickshell
- systemd

Quickshell is checked at runtime so a stale binary that is incompatible with the current Qt version is detected before odyssey is activated.

## Issues and feedback

odyssey is under active development and feedback during the public alpha is welcome.

When reporting an issue, please include:

- a description of the problem
- steps to reproduce it
- relevant terminal or journal output
- your Hyprland version
- your Quickshell version

## Status

odyssey is a **public alpha**.

The core desktop experience is functional, but some areas remain under active development and features or configuration may change between releases.

Expect occasional rough edges while the project matures.

## License

odyssey is licensed under the [GNU General Public License v3.0](LICENSE).
