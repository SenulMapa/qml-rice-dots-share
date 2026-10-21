import QtQuick

// Pure open/close/toggle state machine for the Wi-Fi/Bluetooth/Audio/tray
// satellites (see island/IslandExpanded.qml, which owns an instance of
// this so satellites work from the overview page, not just the deprecated
// control-center page). No service singletons touched here -- same
// "testable in isolation" shape as components/ArmState.qml -- so
// test-satellite-state.qml can drive it without a real shell running.
//
// Wi-Fi (the LEFT satellite) is independent of the RIGHT satellite, which
// hosts bluetooth/audio/tray and only ever shows one of those three at a
// time -- see island/Island.qml's wifiSatellite/bluetoothSatellite Items.
QtObject {
    id: root

    property bool wifiOpen: false
    // "", "bluetooth", "audio", "energy", "phone", or "tray"
    property string rightSection: ""
    property string trayId: ""

    readonly property bool anyOpen: wifiOpen || rightSection !== ""

    function isOpen(section: string): bool {
        if (section === "wifi")
            return wifiOpen
        if (section.indexOf("tray:") === 0)
            return rightSection === "tray" && trayId === section.slice(5)
        return rightSection === section
    }

    function open(section: string): void {
        if (section === "wifi") {
            wifiOpen = true
            return
        }
        if (section.indexOf("tray:") === 0) {
            rightSection = "tray"
            trayId = section.slice(5)
            return
        }
        if (section === "bluetooth" || section === "audio" || section === "energy"
                || section === "phone") {
            rightSection = section
            trayId = ""
        }
    }

    function closeWifi(): void {
        wifiOpen = false
    }

    function closeRight(): void {
        rightSection = ""
        trayId = ""
    }

    function closeAll(): void {
        closeWifi()
        closeRight()
    }

    function toggle(section: string): void {
        if (section === "wifi") {
            wifiOpen ? closeWifi() : open("wifi")
            return
        }
        if (isOpen(section))
            closeRight()
        else
            open(section)
    }
}
