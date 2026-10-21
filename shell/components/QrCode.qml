import QtQuick
import "qr.js" as Qr

/**
 * QrCode -- renders `text` as a QR code (components/qr.js: byte mode, EC M,
 * versions 1-10). Dark modules on a light plate; scanners need the contrast
 * and a quiet zone, so this is a functional plate, not a card.
 */
Item {
    id: root

    property string text: ""
    property color darkColor: "#000000"
    property color lightColor: "#ffffff"
    // Quiet zone in modules.
    property int quiet: 2

    readonly property var code: text.length > 0 ? Qr.encode(text) : null
    readonly property bool valid: code !== null
    readonly property int modules: code ? code.size + 2 * quiet : 0

    implicitWidth: 160
    implicitHeight: 160

    onCodeChanged: canvas.requestPaint()
    onDarkColorChanged: canvas.requestPaint()
    onLightColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: false
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = root.lightColor
            ctx.fillRect(0, 0, width, height)
            const qr = root.code
            if (!qr)
                return
            const unit = Math.floor(Math.min(width, height) / root.modules)
            const off = Math.floor((Math.min(width, height) - unit * root.modules) / 2)
            ctx.fillStyle = root.darkColor
            for (let r = 0; r < qr.size; r++)
                for (let c = 0; c < qr.size; c++)
                    if (qr.get(r, c))
                        ctx.fillRect(off + (c + root.quiet) * unit, off + (r + root.quiet) * unit, unit, unit)
        }
    }
}
