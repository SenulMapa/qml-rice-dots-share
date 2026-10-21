// Offscreen alpha check for the mac Control Center content. Renders MacCcPanel
// on a transparent background to /tmp/shellqa/mac-cc-alpha.png (RGBA), so the
// alpha of the gaps between modules can be sampled. Opens no window, grabs no input.
import QtQuick
import Quickshell
import "core"
import "services"
import "mac"

Item {
    id: root
    width: MacTokens.s(MacTokens.ccGridWidth) + 40
    height: MacTokens.s(MacTokens.ccEditY + MacTokens.ccEditHeight) + 40
    Item {
        x: 20; y: 20
        width: parent.width - 40; height: parent.height - 40
        MacCcPanel { id: panel; x: 0; y: 0 }
    }
    Timer {
        interval: 600; running: true
        onTriggered: {
            root.grabToImage(result => { result.saveToFile("/tmp/shellqa/mac-cc-alpha.png"); Qt.quit() })
        }
    }
}
