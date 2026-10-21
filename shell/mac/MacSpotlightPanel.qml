import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"
import "MacFormat.js" as Fmt

/**
 * MacSpotlightPanel -- the Spotlight content (spec 3.5): a glass panel with a
 * large search field, the Apps / Files / Clipboard / Commands chips and the
 * result list. Pure content: MacSpotlight.qml puts it in a layer window, and
 * the render harness puts it in a plain window.
 *
 * `provider` is CommandPaletteService in the shell (same contract as
 * launcher/LauncherView.qml: search(text, limit), execute(result, copy, new),
 * revision). A stub may replace it in renders and tests.
 */
Item {
    id: root

    required property var provider
    // PhoneService, or a stand-in with findContacts(), openCompose(), dial() and callsEnabled.
    property var phone: PhoneService
    property alias text: searchField.text
    // -1 = every provider. Otherwise an index into `chips`.
    property int chipIndex: -1
    property int currentIndex: 0

    // Chip -> providerId list (launcher/CommandPaletteService.groupRank keys).
    readonly property var chips: [
        { label: "Apps", providers: ["applications"] },
        { label: "Files", providers: ["files"] },
        { label: "Clipboard", providers: ["clipboard"] },
        { label: "Commands", providers: ["odyssey-actions"] }
    ]
    // Filtering happens after the palette search, so ask it for more rows
    // than the list shows; otherwise a busy provider starves a chip.
    readonly property int filterLimit: 200

    // "message <name>" / "call <name>" (MacFormat.phoneRows). Contacts come from
    // PhoneService.findContacts, debounced, and only the newest answer is kept.
    readonly property var phoneIntent: Fmt.phoneIntent(searchField.text)
    property var contactHits: []
    // Overridable so tests can drive the phone rows without Config.phone.
    property bool phoneEnabled: Config.phone.enabled
    readonly property var phoneRowsNow: root.chipIndex < 0
        ? Fmt.phoneRows(root.phoneIntent, root.contactHits, root.phoneEnabled,
            root.phone.callsEnabled === true)
        : []
    property int lookupSeq: 0

    readonly property var results: {
        provider.revision
        const all = provider.search(searchField.text, root.filterLimit)
        const want = root.chipIndex < 0 ? null : root.chips[root.chipIndex].providers
        const picked = want ? all.filter(r => want.indexOf(r.provider) >= 0) : all
        return root.phoneRowsNow.concat(picked).slice(0, Config.launcher.resultLimit)
    }

    signal dismissRequested()
    signal pageRequested(string page)

    // Phone rows are not palette results: they open the compose sheet or dial.
    function activatePhone(row): void {
        if (row.phoneVerb === "call") {
            root.phone.dial(row.phoneNumber, () => {})
        } else {
            root.phone.openCompose(row.phoneName, row.phoneNumber)
            ShellActions.macSurfaceRequested("notifications", "open")
        }
        root.dismissRequested()
    }

    Timer {
        id: lookupDelay
        interval: 200
        repeat: false
        onTriggered: root.lookupContacts()
    }

    function lookupContacts(): void {
        const seq = ++root.lookupSeq
        const intent = root.phoneIntent
        if (!intent || !root.phoneEnabled) {
            root.contactHits = []
            return
        }
        root.phone.findContacts(intent.target, result => {
            if (seq !== root.lookupSeq)
                return
            root.contactHits = (result && result.ok === true) ? (result.contacts || []) : []
        })
    }

    function u(pt: real): real { return MacTokens.s(pt) }

    function firstEnabledIndex(): int {
        for (let i = 0; i < results.length; ++i) {
            if (results[i].enabled !== false)
                return i
        }
        return -1
    }

    function moveSelection(delta: int): void {
        if (results.length === 0)
            return
        let candidate = currentIndex
        for (let i = 0; i < results.length; ++i) {
            candidate = (candidate + delta + results.length) % results.length
            if (results[candidate].enabled !== false)
                break
        }
        currentIndex = candidate
        resultList.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function activateCurrent(newInstance: bool): void {
        if (currentIndex < 0 || currentIndex >= results.length)
            return
        if (results[currentIndex].phoneVerb) {
            if (results[currentIndex].enabled !== false)
                root.activatePhone(results[currentIndex])
            return
        }
        const outcome = provider.execute(results[currentIndex], false, newInstance)
        if (!outcome?.handled)
            return
        if (outcome.page)
            pageRequested(outcome.page)
        else if (outcome.dismiss)
            dismissRequested()
    }

    function toggleChip(index: int): void {
        chipIndex = chipIndex === index ? -1 : index
    }

    // Called by the window when it opens: an empty query, focus in the field.
    function reset(): void {
        searchField.text = ""
        chipIndex = -1
        currentIndex = 0
        Qt.callLater(() => searchField.forceActiveFocus())
    }

    onResultsChanged: currentIndex = Math.max(0, firstEnabledIndex())

    width: u(MacTokens.spotlightWidth)
    height: u(MacTokens.spotlightHeight)

    // Swallows clicks on the empty panel so they never reach the outside-click
    // dismiss area behind it.
    MouseArea {
        anchors.fill: parent
    }

    TahoeSurface {
        id: surface
        kind: "spotlight"
        tintAlpha: MacTokens.spotlightTintAlpha
        anchors.fill: parent
        radius: root.u(MacTokens.spotlightRadius)
    }

    // ---- search row --------------------------------------------------------
    Icon {
        id: magnifier
        x: root.u(MacTokens.spotlightInset)
        y: root.u(MacTokens.spotlightSeparatorY / 2) - size / 2
        name: "search"
        size: root.u(MacTokens.spotlightMagnifierSize)
        color: MacTokens.onSurface(0.55)
    }

    TextInput {
        id: searchField
        x: root.u(MacTokens.spotlightInset + MacTokens.spotlightMagnifierSize + 16)
        y: 0
        width: root.u(MacTokens.spotlightWidth - MacTokens.spotlightInset) - x
        height: root.u(MacTokens.spotlightSearchHeight + 15)
        verticalAlignment: TextInput.AlignVCenter
        color: MacTokens.onSurface(0.85)
        selectionColor: Qt.rgba(0, 0, 0, 0.18)
        selectedTextColor: Qt.rgba(0, 0, 0, 0.85)
        clip: true
        selectByMouse: true
        font.family: MacTokens.textFamily
        font.pixelSize: root.u(MacTokens.spotlightQuerySize)
        onTextChanged: {
            root.contactHits = []
            lookupDelay.restart()
        }

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: searchField.text.length === 0
            text: "Search"
            color: MacTokens.onSurface(0.35)
            font: searchField.font
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Shift+Enter: a new instance of a running app.
                root.activateCurrent((event.modifiers & Qt.ShiftModifier) !== 0)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.dismissRequested()
                event.accepted = true
            }
        }
    }

    Rectangle {
        id: separator
        x: root.u(MacTokens.spotlightInset)
        y: root.u(MacTokens.spotlightSeparatorY)
        width: root.u(MacTokens.spotlightSearchWidth)
        height: 1
        color: MacTokens.onSurface(0.2)
    }

    // ---- chips -------------------------------------------------------------
    Row {
        id: chipRow
        x: root.u(MacTokens.spotlightInset)
        y: root.u(MacTokens.spotlightChipTop)
        spacing: root.u(MacTokens.spotlightChipGap)

        Repeater {
            model: root.chips
            delegate: Rectangle {
                id: chip
                required property int index
                required property var modelData
                readonly property bool active: root.chipIndex === index
                width: (root.u(MacTokens.spotlightSearchWidth) - 3 * root.u(MacTokens.spotlightChipGap)) / 4
                height: root.u(MacTokens.spotlightChipHeight)
                radius: root.u(MacTokens.spotlightChipRadius)
                color: active ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.45)
                scale: chipTap.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    color: chip.active ? Qt.rgba(0, 0, 0, 0.85) : Qt.rgba(0, 0, 0, 0.5)
                    font.family: MacTokens.textFamily
                    font.pixelSize: root.u(MacTokens.spotlightChipTextSize)
                }

                TapHandler {
                    id: chipTap
                    onTapped: root.toggleChip(chip.index)
                }
            }
        }
    }

    // ---- results -----------------------------------------------------------
    ListView {
        id: resultList
        x: root.u(MacTokens.spotlightListInset)
        y: root.u(MacTokens.spotlightSeparatorY + 46)
        width: root.width - 2 * root.u(MacTokens.spotlightListInset)
        height: root.height - y - root.u(10)
        clip: true
        spacing: root.u(MacTokens.spotlightRowGap)
        model: root.results
        currentIndex: root.currentIndex
        boundsBehavior: Flickable.StopAtBounds

        delegate: MacSpotlightResult {
            required property int index
            required property var modelData
            width: resultList.width
            result: modelData
            selected: index === root.currentIndex
            onPointed: root.currentIndex = index
            onActivated: {
                root.currentIndex = index
                root.activateCurrent(false)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: "No Results"
            color: MacTokens.onSurface(0.45)
            font.family: MacTokens.textFamily
            font.pixelSize: root.u(MacTokens.spotlightSubtitleSize)
        }
    }
}
