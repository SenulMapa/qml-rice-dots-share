pragma Singleton
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * WidgetStore -- registry + persisted layout for the Pixel-style desktop
 * widgets (widgets/*). One JSON file, keyed by screen name, holds each
 * widget's type/position(fraction)/size-variant/options. widgets/WidgetHost
 * reads layoutFor(screenName) and calls the mutators below; nothing here
 * knows about PanelWindow/Shapes/etc, so this stays testable as pure logic
 * (see test-widgets.qml).
 *
 * Persistence path: XDG_STATE_HOME if set, else HOME + "/.local/state",
 * + "/qml-rice/widgets.json". Deliberately NOT StandardPaths.GenericStateLocation
 * (see SettingsStore) -- this needs the plain env-var-first resolution.
 */
QtObject {
    id: root

    // ---- registry -----------------------------------------------------
    // requiresBattery-gated entries are simply absent from availableTypes()
    // when there's no battery -- BatteryRingWidget.qml is never even
    // Loader-activated in that case (see widgets/WidgetHost.qml).
    readonly property var registry: [
        { type: "shapeClock", label: "Clock", defaultSize: "3x3", requiresBattery: false },
        { type: "dateWeather", label: "Date & weather", defaultSize: "2x2", requiresBattery: false },
        { type: "media", label: "Media", defaultSize: "3x2", requiresBattery: false },
        { type: "batteryRing", label: "Battery", defaultSize: "2x2", requiresBattery: true },
        { type: "analogClock", label: "Analog clock", defaultSize: "3x3", requiresBattery: false },
        { type: "digitalClock", label: "Digital clock", defaultSize: "3x2", requiresBattery: false },
        { type: "calendar", label: "Calendar", defaultSize: "4x4", requiresBattery: false },
        { type: "todo", label: "To-do", defaultSize: "4x4", requiresBattery: false },
        { type: "pomodoro", label: "Pomodoro", defaultSize: "2x2", requiresBattery: false },
        { type: "systemMonitor", label: "System monitor", defaultSize: "2x2", requiresBattery: false }
    ]

    function availableTypes(): var {
        return root.registry.filter(entry => !entry.requiresBattery
            || BatteryService.available)
    }

    function typeInfo(type: string): var {
        for (const entry of root.registry)
            if (entry.type === type)
                return entry
        return null
    }

    // ---- grid / size variants ------------------------------------------
    readonly property int gridSize: 8
    readonly property int cellSize: 88
    readonly property var sizeVariants: ({
        "2x2": { w: 2, h: 2 },
        "3x2": { w: 3, h: 2 },
        "3x3": { w: 3, h: 3 },
        "4x2": { w: 4, h: 2 },
        "4x4": { w: 4, h: 4 }
    })

    function widgetPixelSize(sizeKey: string): var {
        const variant = root.sizeVariants[sizeKey] || root.sizeVariants["2x2"]
        return { width: variant.w * root.cellSize, height: variant.h * root.cellSize }
    }

    // Snap a raw drag position (px, top-left) to the grid and clamp it
    // fully inside the screen with a margin -- shared by WidgetFrame's live
    // drag and by anything that wants to validate a position offline (unit
    // tests included, no screen required).
    function snapPositionPx(xPx: real, yPx: real, screenW: real, screenH: real,
            widgetW: real, widgetH: real, margin: real): var {
        const g = root.gridSize
        let x = Math.round(xPx / g) * g
        let y = Math.round(yPx / g) * g
        const maxX = Math.max(margin, screenW - widgetW - margin)
        const maxY = Math.max(margin, screenH - widgetH - margin)
        x = Math.max(margin, Math.min(maxX, x))
        y = Math.max(margin, Math.min(maxY, y))
        return { x: x, y: y }
    }

    // ---- default layout --------------------------------------------------
    // Screen-agnostic (fraction-based) so it looks reasonable at any
    // resolution -- both widgets sit against the left edge, clear of the
    // top-centre island pill which never extends past mid-screen width.
    function defaultLayout(): var {
        return [
            { id: "default-shape-clock", type: "shapeClock",
                x: 0.05, y: 0.08, size: "3x3", options: {} },
            { id: "default-date-weather", type: "dateWeather",
                x: 0.05, y: 0.42, size: "2x2", options: {} }
        ]
    }

    // ---- state ----------------------------------------------------------
    property var layouts: ({})
    property bool loaded: false
    property bool editMode: false

    function layoutFor(screenName: string): var {
        const list = root.layouts[screenName]
        return Array.isArray(list) ? list : []
    }

    // Seeds a screen's layout the first time it's ever seen. Only the
    // primary screen gets the default clock+weather pair; every other
    // screen starts empty. A no-op once the screen key exists at all
    // (including an explicitly emptied layout -- removing every default
    // widget must not keep coming back).
    function ensureScreenSeeded(screenName: string, isPrimary: bool): void {
        // Deliberately NOT gated on root.loaded: if this runs before the
        // FileView finishes loading, load()'s onLoaded handler unconditionally
        // replaces root.layouts wholesale from disk right after, so any
        // premature seed here is harmless and gets superseded. Not gating on
        // it also keeps this function pure enough to unit test without
        // touching disk (see test-widgets.qml).
        if (screenName.length === 0)
            return
        if (root.layouts[screenName] !== undefined)
            return
        root.setLayoutForScreen(screenName, isPrimary ? root.defaultLayout() : [])
    }

    function setLayoutForScreen(screenName: string, list: var): void {
        const updated = Object.assign({}, root.layouts)
        updated[screenName] = list
        root.layouts = updated
        root.save()
    }

    function nextWidgetId(type: string): string {
        return type + "-" + Date.now() + "-" + Math.floor(Math.random() * 10000)
    }

    // Staggers each newly-added widget's spawn point so N adds in a row
    // don't all land on the exact same fraction (previously a fixed
    // 0.06/0.06 for every call) -- until the user drags the first one away,
    // every widget after it is perfectly coincident, invisible on top of
    // one another, and dragging only ever moves whichever is stacked
    // highest. Cycles through a few diagonal offsets and wraps well inside
    // the 0..1 fraction range so it never drifts off-screen.
    function addWidget(screenName: string, type: string): string {
        const info = root.typeInfo(type)
        if (!info)
            return ""
        const current = root.layoutFor(screenName).slice()
        const id = root.nextWidgetId(type)
        const step = current.length % 6
        current.push({ id: id, type: type,
            x: 0.06 + step * 0.03, y: 0.06 + step * 0.03,
            size: info.defaultSize, options: {} })
        root.setLayoutForScreen(screenName, current)
        return id
    }

    function removeWidget(screenName: string, id: string): void {
        const current = root.layoutFor(screenName).filter(w => w.id !== id)
        root.setLayoutForScreen(screenName, current)
    }

    function moveWidgetFraction(screenName: string, id: string,
            xFraction: real, yFraction: real): void {
        const current = root.layoutFor(screenName).map(w => w.id === id
            ? Object.assign({}, w, { x: xFraction, y: yFraction }) : w)
        root.setLayoutForScreen(screenName, current)
    }

    function resizeWidget(screenName: string, id: string, sizeKey: string): void {
        if (!root.sizeVariants[sizeKey])
            return
        const current = root.layoutFor(screenName).map(w => w.id === id
            ? Object.assign({}, w, { size: sizeKey }) : w)
        root.setLayoutForScreen(screenName, current)
    }

    function setWidgetOption(screenName: string, id: string, key: string,
            value: var): void {
        const current = root.layoutFor(screenName).map(w => {
            if (w.id !== id)
                return w
            const options = Object.assign({}, w.options || {})
            options[key] = value
            return Object.assign({}, w, { options: options })
        })
        root.setLayoutForScreen(screenName, current)
    }

    function setEditMode(enabled: bool): void {
        root.editMode = enabled
    }

    function toggleEditMode(): void {
        root.editMode = !root.editMode
    }

    // ---- persistence ------------------------------------------------------
    // Params are optional overrides purely so test-widgets.qml can exercise
    // both branches deterministically regardless of this machine's actual
    // (env-set) XDG_STATE_HOME -- real callers (statePath below) always call
    // it with no arguments and get the real env.
    function resolveStateRoot(stateHomeOverride, homeOverride): string {
        const explicit = stateHomeOverride !== undefined
            ? stateHomeOverride : (Quickshell.env("XDG_STATE_HOME") || "")
        if (explicit.length > 0)
            return explicit
        const home = homeOverride !== undefined
            ? homeOverride : (Quickshell.env("HOME") || "")
        return home + "/.local/state"
    }

    readonly property string statePath: resolveStateRoot() + "/qml-rice/widgets.json"

    function serialize(): string {
        return JSON.stringify({ version: 1, screens: root.layouts }, null, 2)
    }

    // Pure parse (no FileView involved) so the round-trip is unit-testable
    // without touching disk.
    function deserialize(raw: string): var {
        try {
            const parsed = JSON.parse(raw)
            return (parsed && typeof parsed.screens === "object"
                && parsed.screens !== null) ? parsed.screens : ({})
        } catch (error) {
            return ({})
        }
    }

    function save(): void {
        if (!root.loaded)
            return
        layoutFile.setText(root.serialize())
    }

    function load(raw: string): void {
        root.layouts = root.deserialize(raw)
        root.loaded = true
    }

    property FileView layoutFile: FileView {
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: error => {
            root.loaded = true
            if (error !== FileViewError.FileNotFound)
                console.warn("qml-rice WidgetStore:", FileViewError.toString(error))
        }
        onSaveFailed: error => console.warn("qml-rice WidgetStore:",
            FileViewError.toString(error))
    }

    // ---- IPC --------------------------------------------------------------
    // `qs -p ./shell.qml ipc call widgets edit` toggles edit mode. A
    // settings/dashboard entry can drive the same thing directly via
    // WidgetStore.setEditMode(bool)/toggleEditMode() -- see the report for
    // exactly where to wire that in panels/SettingsPage.qml (not touched
    // here; that file belongs to another agent).
    property IpcHandler widgetsIpc: IpcHandler {
        target: "widgets"

        function edit(): string {
            root.toggleEditMode()
            return root.editMode ? "WIDGETS_EDIT_ON" : "WIDGETS_EDIT_OFF"
        }

        function status(): string {
            return root.editMode ? "WIDGETS_EDIT_ON" : "WIDGETS_EDIT_OFF"
        }
    }
}
