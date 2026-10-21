// Unit tests for ApplicationService.scopeName/scopedCommand: launched apps go
// to their own systemd scope via ~/.local/bin/app-scope when that helper
// exists (laptop profile), else uwsm, else a plain exec. Pure logic: nothing
// is launched.
import QtQuick
import "applications"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    readonly property var valid: /^[a-z0-9][a-z0-9._-]{0,40}$/

    Component.onCompleted: {
        const n = id => ApplicationService.scopeName(id)
        ok("plain_id_kept", n("firefox") === "firefox")
        ok("lowercased", n("org.gnome.Nautilus") === "org.gnome.nautilus", n("org.gnome.Nautilus"))
        ok("desktop_suffix_dropped", n("kitty.desktop") === "kitty")
        ok("spaces_folded", n("My App") === "my-app", n("My App"))
        ok("leading_junk_stripped", n("-_.zen") === "zen", n("-_.zen"))
        ok("empty_falls_back", n("") === "app" && n(undefined) === "app" && n("~~~") === "app")
        const long = n("a".repeat(80))
        ok("length_capped", long.length === 41 && root.valid.test(long))
        for (const id of ["Zen Browser!", "com.mitchellh.ghostty", "1password", "électron app", "x/y;rm -rf"])
            ok("valid_" + id, root.valid.test(n(id)), n(id))

        const argv = ApplicationService.scopedCommand("Foo Bar", ["foo", "--x", "a b"])
        ok("wrapper_is_sh", argv[0] === "sh" && argv[1] === "-c" && argv[3] === "sh")
        ok("name_is_first_arg", argv[4] === "foo-bar", argv[4])
        ok("command_passed_verbatim", JSON.stringify(argv.slice(5)) === JSON.stringify(["foo", "--x", "a b"]))
        ok("helper_path_runtime_home", argv[2].indexOf('"$HOME/.local/bin/app-scope"') >= 0
            && argv[2].indexOf('[ -x "$s" ]') >= 0)
        ok("app_scope_before_uwsm", argv[2].indexOf("app-scope") < argv[2].indexOf("uwsm"))

        console.log("=== APP SCOPE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.quit()
    }
}
