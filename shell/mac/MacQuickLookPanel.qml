import QtQuick
import QtMultimedia
import "../components"
import "../core"
import "QuickLookFormat.js" as QL

/**
 * MacQuickLookPanel -- the Quick Look content: an opaque ink surface with a
 * header (file name, position in the folder, "Open with default app") and a
 * preview body chosen by kind. Pure content: MacQuickLookWindow.qml puts it in
 * a layer window, and a render harness can put it in a plain window.
 *
 * Keys: Space and Esc emit closeRequested; Left/Up and Right/Down emit
 * stepRequested(-1 / +1). The owner (MacQuickLook) does the navigating.
 */
Item {
    id: root

    property string path: ""
    property string name: QL.nameOf(path)
    property string kind: QL.kindOf(name)
    // Set by MacQuickLook from `stat`, `find`, `head` and `pdftoppm`.
    property var info: null
    property string textPreview: ""
    property bool textBinary: false
    property string pdfPng: ""
    property string pdfError: ""
    // 1-based position in the folder listing, and the folder size. 0 = unknown.
    property int position: 0
    property int count: 0

    signal closeRequested()
    signal stepRequested(int delta)
    signal openRequested()

    function u(pt: real): real { return MacTokens.s(pt) }

    readonly property string sizeText: info && !info.failed ? QL.formatSize(info.bytes) : ""
    readonly property string modifiedText: info && !info.failed && info.modifiedMs > 0
        ? Qt.formatDateTime(new Date(info.modifiedMs), "d MMM yyyy, HH:mm") : ""
    readonly property string kindText: QL.kindLabel(name, info ? info.isDirectory : false)

    implicitWidth: u(MacTokens.quickLookWidth)
    implicitHeight: u(MacTokens.quickLookHeight)

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.stepRequested(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.stepRequested(-1)
            event.accepted = true
        }
    }

    TahoeSurface {
        id: surface
        kind: "quicklook"
        anchors.fill: parent
        radius: root.u(MacTokens.quickLookRadius)

        // Header: name on the left, the Open button on the right.
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.u(MacTokens.quickLookHeaderHeight)

            Text {
                textFormat: Text.PlainText   // file names and contents are untrusted
                id: title
                anchors { left: parent.left; leftMargin: root.u(MacTokens.quickLookPad)
                    right: openButton.left; rightMargin: root.u(10); verticalCenter: parent.verticalCenter }
                text: root.name
                elide: Text.ElideMiddle
                color: MacTokens.labelPrimary
                font.family: MacTokens.textFamily
                font.pixelSize: root.u(MacTokens.quickLookTitleSize)
                font.weight: Font.DemiBold
            }

            Text {
                textFormat: Text.PlainText   // file names and contents are untrusted
                anchors { left: title.left; top: title.bottom; topMargin: 0 }
                visible: root.position > 0 && root.count > 0
                text: root.position + " of " + root.count
                color: MacTokens.labelSecondary
                font.family: MacTokens.textFamily
                font.pixelSize: root.u(MacTokens.quickLookMetaSize - 1)
            }

            Rectangle {
                id: openButton
                anchors { right: parent.right; rightMargin: root.u(MacTokens.quickLookPad)
                    verticalCenter: parent.verticalCenter }
                width: openLabel.implicitWidth + root.u(22)
                height: root.u(26)
                radius: height / 2
                color: openArea.containsMouse ? MacTokens.onSurface(0.2) : MacTokens.onSurface(0.12)
                Text {
                    textFormat: Text.PlainText   // file names and contents are untrusted
                    id: openLabel
                    anchors.centerIn: parent
                    text: "Open with default app"
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: root.u(MacTokens.quickLookMetaSize)
                    font.weight: Font.Medium
                }
                MouseArea {
                    id: openArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openRequested()
                }
            }
        }

        // Body: one preview per kind, chosen by the file's extension.
        Item {
            id: body
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                top: header.bottom
                margins: root.u(MacTokens.quickLookPad)
            }
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: {
                    if (root.kind === "image") return imagePreview
                    if (root.kind === "video") return videoPreview
                    if (root.kind === "audio") return audioPreview
                    if (root.kind === "pdf") return pdfPreview
                    if (root.kind === "text" && !root.textBinary && root.info && !root.info.failed) return textPreview
                    return filePreview
                }
            }
        }
    }

    Component {
        id: imagePreview
        Image {
            source: root.path === "" ? "" : QL.fileUrl(root.path)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
        }
    }

    Component {
        id: videoPreview
        Item {
            Video {
                id: video
                anchors.fill: parent
                source: root.path === "" ? "" : QL.fileUrl(root.path)
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                autoPlay: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: video.playbackState === MediaPlayer.PlayingState ? video.pause() : video.play()
            }
        }
    }

    Component {
        id: audioPreview
        Item {
            MediaPlayer {
                id: player
                source: root.path === "" ? "" : QL.fileUrl(root.path)
                audioOutput: AudioOutput { }
                Component.onCompleted: play()
            }
            Column {
                anchors.centerIn: parent
                spacing: root.u(18)
                Text {
                    textFormat: Text.PlainText   // file names and contents are untrusted
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.name
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: root.u(MacTokens.quickLookTitleSize + 2)
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.u(64)
                    height: width
                    radius: width / 2
                    color: MacTokens.accentBlue
                    Text {
                        textFormat: Text.PlainText   // file names and contents are untrusted
                        anchors.centerIn: parent
                        text: player.playbackState === MediaPlayer.PlayingState ? "II" : ">"
                        color: MacTokens.accentOn
                        font.family: MacTokens.textFamily
                        font.pixelSize: root.u(20)
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                }
            }
        }
    }

    Component {
        id: pdfPreview
        Item {
            Image {
                anchors.fill: parent
                visible: root.pdfPng !== ""
                source: root.pdfPng === "" ? "" : QL.fileUrl(root.pdfPng)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }
            Text {
                textFormat: Text.PlainText   // file names and contents are untrusted
                anchors.centerIn: parent
                visible: root.pdfPng === ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.pdfError !== "" ? root.pdfError : "Rendering page 1..."
                color: MacTokens.labelSecondary
                font.family: MacTokens.textFamily
                font.pixelSize: root.u(MacTokens.quickLookMetaSize + 1)
            }
        }
    }

    // First 200 lines, monospace, clipped on the right instead of wrapped.
    Component {
        id: textPreview
        Flickable {
            contentWidth: code.paintedWidth
            contentHeight: code.paintedHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: code
                text: root.textPreview
                textFormat: Text.PlainText
                color: MacTokens.labelPrimary
                font.family: Config.monoFontFamily
                font.pixelSize: root.u(MacTokens.quickLookMetaSize + 1)
                lineHeight: 1.25
            }
        }
    }

    // Everything else: a large icon with the extension, then the metadata rows.
    Component {
        id: filePreview
        Item {
            Squircle {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: root.u(40)
                width: root.u(MacTokens.quickLookIconSize)
                height: width * 1.25
                radius: root.u(18)
                color: MacTokens.onSurface(0.08)
                borderWidth: 1
                borderColor: MacTokens.onSurface(0.16)
                Text {
                    textFormat: Text.PlainText   // file names and contents are untrusted
                    anchors.centerIn: parent
                    text: root.info && root.info.isDirectory ? "DIR" : QL.extensionOf(root.name).toUpperCase()
                    color: MacTokens.labelSecondary
                    font.family: MacTokens.textFamily
                    font.pixelSize: root.u(18)
                    font.weight: Font.DemiBold
                }
            }
            Column {
                anchors { top: icon.bottom; topMargin: root.u(24); horizontalCenter: parent.horizontalCenter }
                width: parent.width
                spacing: root.u(8)
                Text {
                    textFormat: Text.PlainText   // file names and contents are untrusted
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: root.name
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: root.u(MacTokens.quickLookTitleSize + 2)
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: [
                        { label: "Size", value: root.sizeText },
                        { label: "Modified", value: root.modifiedText },
                        { label: "Kind", value: root.kindText }
                    ]
                    delegate: Text {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.value !== ""
                        text: modelData.label + "   " + modelData.value
                        textFormat: Text.PlainText   // file names and contents are untrusted
                        color: MacTokens.labelSecondary
                        font.family: MacTokens.textFamily
                        font.pixelSize: root.u(MacTokens.quickLookMetaSize)
                    }
                }
            }
        }
    }
}
