pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

/**
 * PaletteAutoService — keeps Theme's fallback palette actually derived from
 * a real wallpaper, instead of the hardcoded Material defaults baked into
 * Theme.qml's fallbackDark/fallbackLight.
 *
 * This shell's own wallpaper picker (WallpaperService) already produces a
 * live, matugen-generated palette when the user picks a wallpaper through
 * THIS shell's dashboard -- but that never happens on a machine where a
 * different rice (or none) owns the desktop background, which is the common
 * case here. That left Theme.generatedAvailable permanently false and every
 * correctly Theme-role-driven accent in the shell (primary, tertiary,
 * warning, ...) rendering the same static lavender/pink/orange fallback
 * regardless of the actual wallpaper.
 *
 * This service closes that gap WITHOUT ever touching the wallpaper itself:
 * it only reads a wallpaper path (never renders/applies one -- that stays
 * exclusively WallpaperService's job, gated behind explicit user action) and
 * feeds it to matugen via the existing scripts/generate-palette.sh helper,
 * which is pure colour extraction with no display side effects at all.
 *
 * Discovery order, read-only, cheapest/most-authoritative first:
 *   1. WallpaperService.currentStill -- this shell's own picker, if the user
 *      has ever used it here. NOT currentWallpaper: when the active
 *      wallpaper is a video, currentWallpaper is the raw .mp4/.webm path and
 *      matugen has no video decoder (it panics with "Unsupported image
 *      format" on anything but a still). currentStill is WallpaperService's
 *      own already-extracted cached frame for exactly this case (see
 *      WallpaperService.qml's currentStillPath/currentStill, and
 *      wallpaperctl.sh's `frame` subcommand that produces it) and is a still
 *      image unconditionally.
 *   2. The well-known caelestia/hyprland-ii wallpaper state symlink, which
 *      is where this machine's actual desktop background renderer records
 *      what it last set. Read via `readlink -f`; never written to. A
 *      foreign renderer's own video wallpaper has no cached still we can
 *      reach, so a candidate that still resolves to a video extension is
 *      dropped rather than handed to matugen.
 * Output goes ONLY to Config.appearance.cacheRoot (~/.cache/qml-rice), never
 * ~/.config and never the interactive picker's own state file. Theme.qml
 * already treats that path as its fallback-palette FileView with
 * watchChanges: true, so writing it is the entire integration -- no changes
 * to Theme.qml itself are needed.
 *
 * ROOT CAUSE (diagnosed 2026-09-20): this service used to read
 * WallpaperService.currentWallpaper and the raw external symlink, both of
 * which point straight at the video file while a video wallpaper is active
 * (confirmed live: ~/.local/state/odyssey/current-wallpaper resolved to
 * .../Animated/cyberpunk-girl-1-moewalls-com.mp4, and `matugen image
 * <that .mp4>` panics immediately with "Unsupported image format"). Every
 * poll therefore re-ran generate-palette.sh against the video and it failed
 * every single time, logging "Odyssey: wallpaper palette auto-generation
 * failed" on every reload. A second bug compounded it: `lastGeneratedFor`
 * was recorded BEFORE the process even ran, so once a path was tried once it
 * was never retried even after a transient failure resolved itself.
 */
QtObject {
    id: root

    readonly property string externalWallpaperLink:
        Quickshell.env("HOME") + "/.local/state/caelestia/wallpaper/current"

    // Same test WallpaperService.currentWallpaperIsVideo already applies to
    // its own raw path; kept in sync manually since this reads a different
    // candidate.
    function isVideoPath(path: string): bool {
        return !!(path && path.match(/\.(mp4|webm|mkv|mov)$/i))
    }

    property string lastGeneratedFor: ""

    function start(): void {
        requestGeneration()
    }

    function requestGeneration(): void {
        // Gated on the same setting Theme.qml already checks before using
        // `generated`: no point extracting a palette nothing will read.
        if (!Config.appearance.wallpaperPaletteEnabled)
            return
        if (resolveProcess.running)
            return
        resolveProcess.running = true
    }

    function maybeGenerate(path: string): void {
        if (!path || path === root.lastGeneratedFor || generateProcess.running)
            return
        // No still frame reachable for this candidate (a foreign renderer's
        // video wallpaper with no extracted frame of its own) -- skip rather
        // than feed matugen a format it cannot decode. Left un-cached in
        // lastGeneratedFor on purpose: WallpaperService may finish extracting
        // its own frame moments later, or the video may switch to a still, so
        // the next poll should try again rather than being permanently stuck.
        if (root.isVideoPath(path)) {
            console.warn("Odyssey: wallpaper palette auto-generation skipped, no still frame for video wallpaper:", path)
            return
        }
        generateProcess.command = [
            Quickshell.shellDir + "/scripts/generate-palette.sh",
            path, Config.wallpaper.scheme, Config.appearance.fallbackPalettePath
        ]
        generateProcess.pendingPath = path
        generateProcess.running = true
    }

    // Step 1: resolve a candidate wallpaper path, read-only. This shell's own
    // still (video-safe) takes priority; the external symlink is a fallback
    // for when a different rice/renderer owns the desktop background, and is
    // rejected outright if it still points at a video.
    property Process resolveProcess: Process {
        // `test -f` because the external link is a foreign rice's (caelestia's)
        // and is simply absent on a machine that never had it -- readlink -f
        // still echoes the unresolved path, which then reached
        // generate-palette.sh as a nonexistent file and failed there, once per
        // reload, with "wallpaper palette auto-generation failed". Printing
        // nothing instead makes maybeGenerate()'s `!path` guard skip it until
        // WallpaperService reports its own STILL= frame (see
        // scripts/wallpaperctl.sh's report_current), which is what should
        // drive the palette anyway.
        command: ["sh", "-c",
            `p=$(readlink -f '${root.externalWallpaperLink}' 2>/dev/null); `
            + `[ -f "$p" ] && printf %s "$p"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const external = text.trim()
                const own = WallpaperService.currentStill
                const resolved = own || (root.isVideoPath(external) ? "" : external)
                root.maybeGenerate(resolved)
            }
        }
    }

    // Step 2: pure colour extraction (matugen) -- never renders/applies
    // anything, so this never touches the visible desktop background.
    property Process generateProcess: Process {
        // Set by maybeGenerate() right before `running` flips true; only
        // committed to lastGeneratedFor on a confirmed success so a
        // transient failure (matugen busy, wallpaper mid-write) gets retried
        // on the next poll instead of being cached as permanently done.
        property string pendingPath: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                root.lastGeneratedFor = root.generateProcess.pendingPath
                root.maybeRepaintApps()
            } else {
                console.warn("Odyssey: wallpaper palette auto-generation failed")
            }
        }
    }

    // Ported from impasto's ThemeService.pushTerminal(): once a palette
    // exists, push it into kitty/foot too -- but only when the user has
    // opted in (Config.appearance.repaintApps, default false), since unlike
    // everything else here this DOES write into ~/.config. The shell decides
    // whether to pass --apply; the script itself never touches ~/.config
    // without it.
    function maybeRepaintApps(): void {
        if (!Config.appearance.repaintApps)
            return
        repaintAppsProcess.command = [
            Quickshell.shellDir + "/scripts/repaint-terminals.py",
            Config.appearance.fallbackPalettePath, "--apply"
        ]
        repaintAppsProcess.running = true
        zenRepaintProcess.command = [
            Quickshell.shellDir + "/scripts/repaint-zen.py",
            Config.appearance.fallbackPalettePath
        ]
        zenRepaintProcess.running = true
    }

    property Process repaintAppsProcess: Process {
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("Odyssey: terminal repaint (kitty/foot) failed")
        }
    }

    property Process zenRepaintProcess: Process {
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("Odyssey: zen browser repaint failed")
        }
    }

    // React the moment this shell's OWN picker changes the wallpaper.
    property Connections wallpaperLink: Connections {
        target: WallpaperService
        function onWallpaperApplied(path, paletteUpdated): void {
            if (Config.appearance.wallpaperPaletteEnabled)
                root.maybeGenerate(path)
        }
    }

    // Everything else (a different rice's renderer changing the real
    // background) has no signal this shell can subscribe to, so poll its
    // read-only state file at the same cadence WallpaperService already
    // polls its own backend health.
    property Timer pollTimer: Timer {
        interval: 20000
        repeat: true
        running: true
        onTriggered: root.requestGeneration()
    }
}
