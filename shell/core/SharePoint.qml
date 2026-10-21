import QtQuick

/**
 * SharePoint -- an invisible tag a state drops where it draws a shared
 * element (art / title / clock). island/SharedElements.qml reads these to
 * find the ACTIVE state's rect and morph the one real instance onto it.
 *
 * shareKind  : "art" | "title" | "clock"
 * shareState : the IslandController state (or "dashboard") it belongs to.
 *              Only the state matching SharedElements.stateKey counts.
 * shareLive  : false when the state has nothing to show right now
 *              (eg. no media), so the element fades out instead.
 * measure    : the real item whose rect is the target. Defaults to this tag.
 * shareRadius: art only; -1 means a circle (width / 2).
 * shareScale : text scale for the element, relative to its largest size.
 * shareSubScale: artist line scale (title only).
 */
Item {
    id: root

    property string shareKind: ""
    property string shareState: ""
    property bool shareLive: true
    property Item measure: root
    property real shareRadius: -1
    property real shareScale: 1
    property real shareSubScale: 1
}
