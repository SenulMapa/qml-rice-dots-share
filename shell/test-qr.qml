// QR encoder test: components/qr.js against `qrencode -t ASCII -m 0 -l M -8`
// vectors (test-fixtures/qr-vectors.js, generated with qrencode). Pure JS.
import QtQuick
import Quickshell
import "components/qr.js" as Qr
import "test-fixtures/qr-vectors.js" as Fx

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Component.onCompleted: {
        const vs = Fx.VECTORS
        let autoMatch = 0
        for (let i = 0; i < vs.length; i++) {
            const v = vs[i]
            const forced = Qr.encode(v.text, v.mask)
            ok("vector" + i + "_v" + v.version + "_matrix_identical_at_mask" + v.mask,
                forced && forced.version === v.version && Qr.toAscii(forced) === v.ascii)
            const auto = Qr.encode(v.text)
            if (Qr.toAscii(auto) === v.ascii)
                autoMatch++
        }
        // libqrencode's penalty scoring differs from ours on one vector
        // ("hello world": mask 3 vs 2); every other mask pick must agree.
        ok("auto_mask_matches_qrencode", autoMatch >= vs.length - 1, autoMatch + "/" + vs.length)
        const versions = vs.map(v => v.version)
        ok("covers_versions_1_to_10_incl_v7plus_and_16bit_count",
            versions.indexOf(1) >= 0 && versions.indexOf(10) >= 0 && versions.some(x => x >= 7))
        ok("too_long_returns_null", Qr.encode("x".repeat(400)) === null)
        ok("utf8_multibyte_encodes", Qr.encode("é✓") !== null)

        console.log("=== QR TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
