import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../core"
import "../services"

Item {
    id: root
    required property string itemId
    property bool powerHovered: false
    // Workspace-switch overlay (forwarded from IslandController via
    // IslandDormant) -- only meaningful for itemId === "Clock", see
    // clockComponent below.
    property bool workspaceSwitchActive: false
    // Pill width from IslandDormant; 0 = unconstrained (side rest items).
    property real availableWidth: 0
    // Ink: true only where SharedElements draws the clock (see IslandDormant).
    property bool shareHosted: false
    readonly property bool inkShared: Config.appearance.ink && root.shareHosted
    // The laid-out time Text inside clockComponent (a Loader component, so
    // its id is not reachable from outside). IslandDormant's clock
    // SharePoint measures THIS, not the whole rest item, or the shared clock
    // aims at the pill's dead centre and sits on the lyric line.
    property Item clockMeasure: null
    property int workspaceIndicatorMax: 5
    property int previousWorkspaceId: 1
    signal powerRequested()
    // impasto card pages (DeskSettings.islandImpastoCards): tapping the
    // resting/hover pill's clock opens the calendar card directly -- only
    // meaningful for itemId === "Clock" (clockComponent below), same scope
    // restriction as workspaceSwitchActive above.
    signal calendarRequested()
    // Left-click on the same clock face -- see the TapHandler pair in
    // clockComponent below.
    signal dashboardRequested()
    implicitWidth: contentLoader.item?.implicitWidth ?? 0
    // Width the resting row NEEDS (bars + gutter mirrored on both sides of a
    // truly centred clock), independent of the pill's current width -- the
    // pill sizes itself from this. implicitWidth can't serve: the clock slot's
    // width follows the pill, so it only ever echoed the pill back and the
    // pill never grew enough, letting a centred clock overlap the eq bars.
    readonly property real requiredWidth: contentLoader.item?.requiredWidth ?? implicitWidth
    // 20 was a bare literal (unlike the Theme.u()/restIconScale-derived
    // sizes elsewhere in this file) -- every implicitHeight: 20 below, plus
    // the notification-count dot's width/height: 13 and powerComponent's
    // implicitWidth: 18, are the same fix repeated at each sibling
    // Component, scaled by DisplayScale.primary (core/DisplayScale.qml).
    implicitHeight: Math.round(20 * DisplayScale.primary)

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.itemId === "Weather" ? weatherComponent
            : root.itemId === "Dnd" ? dndComponent
            : root.itemId === "Clock" ? clockComponent
            : root.itemId === "KeepAwake" ? keepAwakeComponent
            : root.itemId === "PowerProfile" ? powerComponent : null
    }

    Component {
        id: weatherComponent
        Item {
            visible: Config.weather.enabled && WeatherService.available
            implicitWidth: Math.round(14 * Config.island.restIconScale)
            implicitHeight: Math.round(20 * DisplayScale.primary)
            Text {
                anchors.centerIn: parent
                text: WeatherService.icon
                color: Theme.tertiary
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(12 * Config.island.restIconScale)
            }
        }
    }

    Component {
        id: dndComponent
        Item {
            implicitWidth: Math.round(14 * Config.island.restIconScale)
            implicitHeight: Math.round(20 * DisplayScale.primary)
            Text {
                visible: NotificationService.count === 0
                anchors.centerIn: parent
                text: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
                color: NotificationService.doNotDisturb
                    ? Theme.tertiary : AdaptiveColor.glassText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            Rectangle {
                visible: NotificationService.count > 0
                anchors.centerIn: parent
                width: Math.round(13 * DisplayScale.primary); height: width; radius: width / 2
                color: Theme.error
                Text { anchors.fill: parent; anchors.leftMargin: 1; text: NotificationService.count > 99 ? "99+" : NotificationService.count; color: Theme.foregroundFor(parent.color); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Config.appearance.monoFontFamily; font.pixelSize: Math.round(7 * Config.island.restTextScale); font.weight: Font.Bold }
            }
            TapHandler { onTapped: NotificationService.toggleDoNotDisturb() }
        }
    }

    Component {
        id: clockComponent
        // The clock plus a level meter, LEFT of the time, bottom-aligned to
        // its baseline -- measured from the reference video: 4 bars, ~3px wide
        // with ~2px gaps, tallest bar exactly equal to the clock's cap height.
        //
        // The meter is ABSENT when nothing is playing, not idling at zero.
        // That is a correctness requirement, not a style choice: an always-on
        // loop repaints the scene graph ~60x a second forever, which measured
        // 6% idle CPU and defeats the frame clock's entire sleep architecture.
        // No music -> no bars -> no repaints -> genuinely idle.
        //
        // CENTRING: eq bars, lyric band and clock sit in a fixed linear strip
        // -- [pad][eq][gutter][lyric band][clock][pad] -- with EQUAL end
        // padding on both sides (owner decision: a balanced pill beats a
        // perfectly centred lyric line). The lyric line's own centre may
        // drift off the pill's true centre as a result; that tradeoff is
        // accepted. This replaced an earlier mirrored-slot scheme that kept
        // the lyric line centred at the cost of unequal end paddings.
        // Outer wrapper: the clock (clockRoot below) and the workspace-switch
        // row (island/WorkspacePillRow.qml) occupy the SAME slot and
        // cross-fade between each other -- never both driving layout at once,
        // hence implicitWidth taking whichever is currently wider so the
        // pill's own spring (IslandController.targetWidth, retargeted via
        // workspaceSwitchActive) never fights a simultaneously-resizing
        // child.
        Item {
            id: clockSlot
            // Size to whichever child is showing: the pill's own width only adds
            // the workspace row while a switch is active, so a max() here made the
            // slot wider than the resting pill and pushed the clock off its left edge.
            implicitWidth: root.workspaceSwitchActive ? workspaceRow.implicitWidth : clockRoot.width
            readonly property real requiredWidth: root.workspaceSwitchActive
                ? workspaceRow.implicitWidth
                : 2 * clockRoot.endPad + 2 * clockRoot.sideRest + clockRoot.timeW
            implicitHeight: Math.round(20 * DisplayScale.primary)

        Item {
            id: clockRoot
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.workspaceSwitchActive ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: Animations.normal; easing.type: Easing.OutCubic }
            }

            // impasto card pages (DeskSettings.islandImpastoCards): the
            // clock face itself is the hit area for the calendar card.
            // Disabled during a workspace-switch flash (clockRoot is
            // opacity 0 and non-interactive then anyway via `visible`
            // above) so a tap never lands on the wrong overlay mid-fade.
            // Left opens the dashboard, right opens the calendar card --
            // the owner's own split. Until now the clock emitted
            // calendarRequested() into a signal island/Island.qml never
            // connected, so a click on the resting pill's middle did
            // nothing at all.
            TapHandler {
                enabled: root.itemId === "Clock" && !root.workspaceSwitchActive
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onTapped: root.dashboardRequested()
            }
            TapHandler {
                enabled: root.itemId === "Clock" && !root.workspaceSwitchActive
                acceptedButtons: Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onTapped: root.calendarRequested()
            }
            readonly property real timeW: timeText.implicitWidth
            readonly property real meterW: eqBar.visible ? eqBar.width : 0
            // Gap between the eq bars and whatever follows -- only present
            // while the meter itself is showing.
            readonly property real meterGutter: meterW > 0 ? 6 : 0
            // Fixed padding from the pill's own edges to the eq-bar ink and
            // to the clock ink -- the SAME value both ends, by construction,
            // and the SAME kPad ratio token island/WorkspacePillRow.qml's
            // own edge padding uses (core/BlobLayout.qml) instead of a
            // separately hand-picked multiplier that happened to look
            // similar (0.4 here vs kPad's 0.36).
            readonly property real endPad: Math.round(
                Config.island.dormantHeight * BlobLayout.kPad)

            // Lay out against the real pill when we know it; else our own size.
            width: root.availableWidth > 0 ? root.availableWidth : clockRoot.implicitWidth
            // TRUE SYMMETRIC CENTRING (owner, 26 Sep: "the centering is always off
            // bro i swear"). The lyric text must sit on the PILL's own centre
            // line, with an available box that is symmetric around that centre
            // by construction -- 2 * min(leftRoom, rightRoom) -- so it can never
            // depend on which side element (eq bars vs clock time) happens to be
            // wider. The old `sideSlot = max(meterW, timeW) + 8` reserved that
            // SAME, larger margin on BOTH sides (even the eq-bar side, which
            // only ever needs meterW + meterGutter), so it shrank fitTextWidth
            // far more than the real geometry required -- pushing lines that
            // would have fit into the AlignLeft/marquee branch below, rendered
            // flush against a box that was itself still centred, i.e. exactly
            // the reported "big gap on the left, small gap on the right" bug.
            //
            // effWidth avoids a binding loop when root.availableWidth is not
            // yet known (0): unlike clockRoot.width, it never reads back
            // fitTextWidth/implicitWidth, so it is always evaluable directly.
            readonly property real effWidth: root.availableWidth > 0
                ? root.availableWidth
                : 2 * endPad + meterW + meterGutter + timeW
                    + Config.media.lyricsBandWidth
            readonly property real halfW: effWidth / 2
            // Minimum visual gutter between the lyric box and EITHER side
            // element (owner, 26 Sep: mathematically centred still read as
            // crowded against the clock -- a 10px gap to the time text next
            // to a wide gap on the bars side). Same value both sides, on top
            // of whatever endPad/meterGutter already reserve -- meterGutter
            // alone (6px) is smaller than this floor, so Math.max keeps the
            // bars side from getting LESS breathing room than the time side
            // just because it happens to have its own, smaller gutter term.
            readonly property real minGutter: Theme.u(0.4)
            readonly property real leftRoom: Math.max(0,
                halfW - endPad - meterW - Math.max(meterGutter, minGutter))
            readonly property real rightRoom: Math.max(0,
                halfW - endPad - timeW - minGutter)
            // Widest lyric line that still leaves both REAL side elements,
            // their end pads AND the minimum gutter clear, capped at the
            // configured fixed-band width.
            // Ink: one symmetric inset per side, equal to the wider of the
            // two real side items (eq bars vs clock time), so the lyric box
            // is centred on the pill whichever side is heavier.
            readonly property int fitTextWidth: Config.appearance.ink
                ? Math.floor(Math.max(0, Math.min(Config.media.lyricsBandWidth,
                    effWidth - 2 * (endPad + Math.max(
                        meterW > 0 ? meterW + Math.max(meterGutter, minGutter) : 0,
                        timeW + minGutter)))))
                : Math.floor(Math.max(0, Math.min(
                    Config.media.lyricsBandWidth, 2 * Math.min(leftRoom, rightRoom))))
            height: clockRoot.implicitHeight
            // lyricBand.width already bakes in its own trailing gutter (see
            // lyricBand below), so the clock simply starts where the band's
            // occupied region ends -- no extra gap term needed here.
            // MIRRORED SLOTS (owner, 17 Sep: "clock still not centred, lyrics still
            // not centred"). Eq and clock get equal-width side slots, so the lyric
            // line sits on the pill's true centre; with no lyrics the clock itself
            // is centred. lyricT (0..1, the band's own spring) blends the two
            // layouts so nothing jumps when lyrics arrive or leave. Denominator
            // matches bandW's own target (fitTextWidth + gap, see lyricBand
            // below) -- NOT the fixed Config.media.lyricsBandWidth -- so lyricT
            // still reaches exactly 1 when the real available room is narrower
            // than that configured cap (hover/narrow-pill states).
            readonly property real lyricT: Math.max(0, Math.min(1, lyricBand.width
                / Math.max(1, fitTextWidth + Config.media.lyricsBandGap)))
            readonly property real textW: Math.max(0, lyricBand.width - Config.media.lyricsBandGap)
            readonly property real sideRest: meterW > 0 ? meterW + Math.max(meterGutter, minGutter) : 0
            readonly property real sideLyric: Math.max(meterW, timeW) + 6
            readonly property real side: sideRest + (sideLyric - sideRest) * lyricT
            implicitWidth: 2 * clockRoot.endPad + 2 * clockRoot.side + clockRoot.textW
                + (1 - clockRoot.lyricT) * clockRoot.timeW
            implicitHeight: Math.round(20 * DisplayScale.primary)

            Eq {
                id: eqBar
                active: MediaService.playing
                visible: MediaService.playing
                anchors.verticalCenter: parent.verticalCenter
                // Left edge sits at the pill's own end pad -- see endPad above.
                x: clockRoot.endPad
                maxH: Math.round(11 * Config.island.restTextScale)
                barColor: Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill
            }
            // Mirrored twin pinned endPad from the RIGHT edge, so the centred
            // clock has matching bars on both sides (owner's pick). Fades out
            // as the lyric band opens, since the time takes the right slot.
            Eq {
                id: eqBarMirror
                active: eqBar.active
                visible: eqBar.visible && opacity > 0.01
                // Any open lyric band hides it outright: lyricT doesn't reach
                // exactly 1 with a real lyric, so a proportional fade left the
                // twin half-visible on top of the right-slotted time.
                opacity: clockRoot.lyricT > 0.01 ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                anchors.verticalCenter: parent.verticalCenter
                x: clockRoot.width - clockRoot.endPad - width
                maxH: eqBar.maxH
                barColor: eqBar.barColor
                transform: Scale { origin.x: eqBarMirror.width / 2; xScale: -1 }
            }
            Item {
                id: lyricBand
                // Lyrics sit BETWEEN the meter and the clock in a FIXED-width
                // band, so the pill never resizes on a line change -- only
                // lyrics on vs off (LyricsService.active) ever moves this
                // target. The band springs open with the island surface's
                // omega/zeta, so the lyrics and the pill widen as one motion.
                // Its trailing lyricsBandGap is the gutter before the clock.
                // clip keeps a departing line from drifting over the clock;
                // the band exists only while lyrics show.
                property MotionValue bandW: MotionValue {
                    unit: "px"
                    zeta: 0.92
                    omega: 12.8 / Math.max(0.25, Config.appearance.motionScale)
                    // Preview override (services/PreviewService.qml's
                    // `lyric` IPC call) also opens the band, so its scroll
                    // and feather can be screenshotted without real lyrics.
                    // Targets the REAL symmetric fitTextWidth (clockRoot,
                    // above), not the raw Config.media.lyricsBandWidth cap --
                    // otherwise this Item's own actual width could disagree
                    // with the value the centring x math below (and
                    // textContent's clip box) was computed against, which
                    // would silently re-introduce an off-centre box even
                    // though each individual formula looked correct in
                    // isolation.
                    target: (LyricsService.active || lyricBand.previewLyricActive)
                        ? clockRoot.fitTextWidth + Config.media.lyricsBandGap
                        : 0
                }
                readonly property int textWidth: clockRoot.fitTextWidth
                property string shownLine: ""
                property string outgoingLine: ""
                property real swap: 1
                // Feather width per edge, as a fraction of textContent's OWN
                // current width (the actual masked/clipped region, not the
                // wider band which also carries the trailing gutter) --
                // keeps both edges soft while the band is mid-spring instead
                // of over-eating a half-open band.
                readonly property real featherFrac: textContent.width > 0
                    ? Math.min(0.49, Theme.u(0.4) / textContent.width) : 0
                // Per-edge fade gating for lyricFeatherMask below: only the
                // edge(s) with real off-screen content at the CURRENT scroll
                // offset should ever fade. At rest (marqueeX === 0, whether
                // waiting out the pre-scroll pause or a line that hasn't
                // started marqueeing yet) the left edge shows the genuine
                // start of the line -- never fade it. Once fully scrolled to
                // -overflow the right edge shows the genuine end -- never
                // fade that either. Both fade together mid-glide, same as
                // before.
                readonly property bool leftFadeActive:
                    incoming.overflow > 0 && incoming.marqueeX < -0.5
                readonly property bool rightFadeActive:
                    incoming.overflow > 0
                    && incoming.marqueeX > -(incoming.overflow - 0.5)

                // Centre the lyric text on the pill.
                x: Math.round((clockRoot.width - lyricBand.textWidth) / 2)
                width: Math.round(bandW.value)
                height: Math.max(incoming.implicitHeight, 14)
                visible: width > 0
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                // The old line dims and rises away; the new one comes up bright.
                // Opacity and offset stay duration clips on purpose: cheap, and
                // a fade is never worth interrupting.
                function present(line): void {
                    if (line === shownLine)
                        return
                    outgoingLine = shownLine
                    shownLine = line
                    incoming.marqueeX = 0
                    marquee.stop()
                    swapAnim.restart()
                    if (incoming.overflow > 0)
                        marquee.restart()
                }

                NumberAnimation {
                    id: swapAnim
                    target: lyricBand
                    property: "swap"
                    from: 0
                    to: 1
                    duration: Config.appearance.reducedMotion ? 0 : 260
                    easing.type: Easing.OutCubic
                }

                // A line longer than the band scrolls once instead of being cut:
                // hold, glide to its end at a readable pace, then rest there.
                SequentialAnimation {
                    id: marquee
                    PauseAnimation { duration: 900 }
                    NumberAnimation {
                        target: incoming
                        property: "marqueeX"
                        to: -incoming.overflow
                        duration: Math.max(600, incoming.overflow * 28)
                        easing.type: Easing.InOutSine
                    }
                }

                // The raw text lives in its own Item, layered with the
                // feather mask applied directly via layer.effect -- this
                // Item IS what's on screen (visible stays true); there is
                // no separate sibling MultiEffect copy that could paint an
                // unmasked, hard-edged duplicate on top of/under it.
                Item {
                    id: textContent
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // Confined to the fixed textWidth, NOT lyricBand.width
                    // (which also bakes in the trailing lyricsBandGap as a
                    // reserved blank strip before the clock). Clipping here
                    // -- the same width the marquee's own overflow math
                    // targets -- keeps a real gutter in front of the clock
                    // for the ENTIRE scroll, not just once the line settles
                    // at rest.
                    width: lyricBand.textWidth
                    // This Item's own bounds are what actually size the
                    // offscreen texture the layer effect samples from, so a
                    // scrolling line that's wider than the band while its
                    // marquee is mid-glide still can't paint past textWidth
                    // and into the gutter/clock before the layer crops it.
                    clip: true
                    // Off while the band itself is springing open/closed
                    // (bandW.active -- driven by the same island omega/zeta
                    // as the surface morph, see lyricBand.bandW above): a
                    // moving MultiEffect-masked layer retextures every
                    // frame for no visual gain mid-motion, since textWidth
                    // is fixed and clip: true above already keeps the text
                    // confined without the soft feather. Re-enabled the
                    // instant the spring settles, when the feather is what
                    // actually matters (steady-state reading/scrolling).
                    //
                    // ALSO off whenever the current line fits (incoming.
                    // overflow === 0): the owner's "first word looks
                    // clipped" complaint was this mask fading the very
                    // start of a line that fit -- see lyricFeatherMask's
                    // per-edge gating below for why this alone isn't
                    // enough on the overflow branch too.
                    layer.enabled: !lyricBand.bandW.active && incoming.overflow > 0
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: lyricFeatherMask
                        // MultiEffect reshapes the mask's raw per-pixel
                        // alpha through smoothstep(threshold-spread,
                        // threshold+spread, alpha) before using it as the
                        // blend weight -- it does NOT just pass the
                        // gradient's own alpha through untouched.
                        // threshold=spread=0.5 makes that window exactly
                        // [0, 1], i.e. smoothstep(0, 1, alpha): 0 stays 0,
                        // 1 stays 1, and everything between is a genuine
                        // monotonic ramp -- a true pass-through of the
                        // gradient below instead of reshaping it.
                        // A small spread (e.g. 0.1) instead compresses that
                        // same 0..1 alpha range into a ~10%-wide window,
                        // collapsing our 18px gradient into a ~2px stroke-
                        // antialiasing-width snap -- visually still a hard
                        // clip. Leaving the max side at its Qt defaults
                        // (threshold 1.0, spread 0.0) is deliberate too: any
                        // spread there puts the plateau's alpha (exactly
                        // 1.0) at the transition's exact midpoint, halving
                        // the whole band's opacity to ~50%.
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                    }

                    Text {
                        id: outgoing
                        width: lyricBand.textWidth
                        text: lyricBand.outgoingLine
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Math.round(12 * Config.island.restTextScale)
                        opacity: 0.5 * (1 - lyricBand.swap)
                        y: Math.round(-6 * lyricBand.swap)
                        visible: opacity > 0.01
                    }
                    Text {
                        id: incoming
                        readonly property real overflow: Math.max(0, implicitWidth - lyricBand.textWidth)
                        property real marqueeX: 0
                        x: overflow > 0 ? marqueeX : 0
                        width: overflow > 0 ? implicitWidth : lyricBand.textWidth
                        text: lyricBand.shownLine
                        horizontalAlignment: overflow > 0 ? Text.AlignLeft : Text.AlignHCenter
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Math.round(12 * Config.island.restTextScale)
                        // An instrumental gap reads quieter than a sung line.
                        opacity: (text === "\u266A" ? 0.5 : 1.0) * lyricBand.swap
                        y: Math.round(6 * (1 - lyricBand.swap))
                    }
                }

                // Horizontal alpha gradient used only as MultiEffect's mask
                // -- transparent at the edge(s) of the band that are ACTUALLY
                // truncated at the current scroll offset, opaque everywhere
                // else, so the scrolling line fades in/out only where there
                // is real off-screen content instead of unconditionally
                // fading both edges of every overflowing line.
                //
                // At marqueeX=0 (line at rest, about to scroll, or a fresh
                // present() that hasn't started yet) the LEFT edge shows the
                // true start of the line -- nothing is cut off there, so it
                // must render at full opacity; only the right edge (which
                // really does run past the box) fades. Symmetric case once
                // fully scrolled to -overflow: the right edge now shows the
                // true end of the line and must not fade, only the left.
                // Getting this wrong is exactly the owner's "first word
                // looks clipped or faded at its left edge" complaint.
                Item {
                    id: lyricFeatherMask
                    width: textContent.width
                    height: textContent.height
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: lyricBand.leftFadeActive ? "transparent" : "white"
                            }
                            GradientStop { position: lyricBand.featherFrac; color: "white" }
                            GradientStop { position: 1 - lyricBand.featherFrac; color: "white" }
                            GradientStop {
                                position: 1.0
                                color: lyricBand.rightFadeActive ? "transparent" : "white"
                            }
                        }
                    }
                }

                readonly property bool previewLyricActive: PreviewService.enabled
                    && PreviewService.lyricOverride.length > 0

                Connections {
                    target: LyricsService
                    function onCurrentLineChanged(): void {
                        if (LyricsService.active && !lyricBand.previewLyricActive)
                            lyricBand.present(LyricsService.currentLine)
                    }
                    function onActiveChanged(): void {
                        if (LyricsService.active && !lyricBand.previewLyricActive)
                            lyricBand.present(LyricsService.currentLine)
                    }
                }
                // Preview override (services/PreviewService.qml's `lyric`
                // IPC call): shows an arbitrary line, long enough to force
                // the band's own marquee, without a real track playing.
                // Clearing it (empty string) falls back to whatever the
                // real service is showing, if anything.
                Connections {
                    target: PreviewService
                    enabled: PreviewService.enabled
                    function onLyricOverrideChanged(): void {
                        if (lyricBand.previewLyricActive)
                            lyricBand.present(PreviewService.lyricOverride)
                        else if (LyricsService.active)
                            lyricBand.present(LyricsService.currentLine)
                    }
                }
                Component.onCompleted: {
                    if (previewLyricActive)
                        present(PreviewService.lyricOverride)
                    else if (LyricsService.active)
                        present(LyricsService.currentLine)
                }
            }
            Text {
                id: timeText
                Component.onCompleted: root.clockMeasure = timeText
                Component.onDestruction: if (root.clockMeasure === timeText) root.clockMeasure = null
                text: ShellState.time
                // Ink: SharedClock (island/SharedElements.qml) draws the time;
                // this stays laid out as the measure for the rest clock.
                opacity: root.inkShared ? 0 : 1
                // Ink: the showcase clock13 (Geist 600, t1).
                color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.clockFontFamily
                font.weight: Config.appearance.ink ? Font.DemiBold : Config.appearance.clockFontWeight
                font.pixelSize: Config.appearance.ink ? 13 : Math.round(13 * Config.island.restTextScale)
                // Proportional digits change advance width every minute, and
                // the clock's position is owned by a spring -- that jitter
                // would fight it once a minute, forever. It is also what
                // keeps clockRoot.timeW (and therefore every position/width
                // above) stable across a minute tick instead of twitching.
                font.features: ({ "tnum": 1 })
                // Lyrics: right slot, pinned endPad from the pill's own edge
                // (rightX). No lyrics: TRUE centre, unconditionally -- see
                // clockRoot's own "TRUE SYMMETRIC CENTRING" comment above.
                // This used to clamp centreX away from the eq bars whenever
                // the true centre sat closer to them than a fixed margin,
                // which read as the clock drifting right for no reason any
                // time bars were showing (the "playing without lyrics"
                // state) -- exactly the kind of side-element-width-dependent
                // bias the new rule forbids. A pill too narrow to clear
                // both bars and a truly centred clock is a pill-sizing
                // problem, not something centring math should paper over by
                // quietly going off-centre.
                readonly property real rightX: clockRoot.width - clockRoot.endPad - clockRoot.timeW
                readonly property real centreX: (clockRoot.width - clockRoot.timeW) / 2
                x: Math.round(clockRoot.lyricT * rightX + (1 - clockRoot.lyricT) * centreX)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        WorkspacePillRow {
            id: workspaceRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pillHeight: Config.island.dormantHeight
            maxWorkspaces: root.workspaceIndicatorMax
            previousWorkspaceId: root.previousWorkspaceId
            opacity: root.workspaceSwitchActive ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: Animations.normal; easing.type: Easing.OutCubic }
            }
        }
        }
    }

    Component {
        id: keepAwakeComponent
        Item {
            implicitWidth: Math.round(14 * Config.island.restIconScale)
            implicitHeight: Math.round(20 * DisplayScale.primary)
            Text {
                anchors.centerIn: parent
                text: "󰅶"
                color: IdleService.inhibited ? Theme.error : AdaptiveColor.glassText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            TapHandler { onTapped: IdleService.toggleInhibition() }
        }
    }

    Component {
        id: powerComponent
        Item {
            implicitWidth: Math.round(18 * DisplayScale.primary)
            implicitHeight: Math.round(20 * DisplayScale.primary)
            Text {
                anchors.centerIn: parent
                text: PowerProfileService.icon
                color: PowerProfileService.profileName === "Performance" ? Theme.warning
                    : PowerProfileService.profileName === "Power saver" ? Theme.success
                    : AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            HoverHandler { onHoveredChanged: root.powerHovered = hovered }
            TapHandler {
                onTapped: root.powerRequested()
            }
        }
    }
}
