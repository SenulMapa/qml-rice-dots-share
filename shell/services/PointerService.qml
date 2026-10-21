pragma Singleton
import QtQuick
import Quickshell

// Desktop.qml's PanelWindow carries a full-screen input mask (`mask: Region
// { width: root.width; height: root.height }`) so a right-click anywhere on
// the desktop opens its menu -- and on Wayland only the topmost surface that
// owns input gets the pointer, so surfaces beneath it (DitherWallpaper's own
// MouseArea, on the Background layer) never see a single hover event while
// the desktop layer is present. Rather than shrink Desktop's mask -- which
// would break "right-click anywhere" -- the surface that actually owns the
// pointer (Desktop.qml) publishes its position here for whoever beneath it
// wants it.
Singleton {
    property bool hovered: false
    property string screenName: ""
    property real x: 0
    property real y: 0
}
