// Unit tests for the Spotlight palette's pure helpers: arithmetic detection
// (launcher/providers/search.js) and the web-search query encoding, plus the
// calculator answer those detected expressions get. Pure logic: nothing is
// opened, copied or launched.
import QtQuick
import "launcher/providers/search.js" as Search
import "launcher/providers/calc.js" as Calc
import "mac/MacFormat.js" as Fmt
import "mac"

Item {
    id: root
    property var log: []

    // The mac Spotlight content, with a palette and phone stand-in (see below).
    Component {
        id: panelComponent
        MacSpotlightPanel {}
    }
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Component.onCompleted: {
        // Plain arithmetic, with and without the operators the calculator knows.
        for (const text of ["2+3", "2 * 3", "10%3", "2^-1", "(1+2)*3", "1.5*4", "2 × 3", "8 ÷ 2", "-(3+1)*2", "2^3^2"])
            ok("arithmetic_" + text, Search.isArithmetic(text), text)

        // Not arithmetic: searches, lone numbers, lone signs, letters, junk.
        for (const text of ["", "   ", "2024", "-5", "5%", "(2)", "2+", "+", "2pi", "sqrt(16)",
                "notes", "app 2", "1//2", "a+b", "2 + x", "1,000", "2".repeat(201) + "+1"])
            ok("not_arithmetic_" + (text.length ? text.slice(0, 12) : "empty"), !Search.isArithmetic(text), JSON.stringify(text.slice(0, 20)))

        // Date shapes are searches or dates, never arithmetic. Two-part
        // fractions and other dashed or slashed sums stay calculator input.
        for (const text of ["2024-01-15", "2024-1-5", "1/2/2024", "12/31/24", "3/4/05"])
            ok("date_not_arithmetic_" + text, !Search.isArithmetic(text), text)
        for (const text of ["1/2", "10-2-3", "2024-01", "1/2/3/4"])
            ok("date_shape_kept_" + text, Search.isArithmetic(text), text)

        // Every shape the detector accepts must evaluate, and to the right answer.
        const answers = { "2+3": "5", "10%3": "1", "2^-1": "0.5", "(1+2)*3": "9", "2 × 3": "6", "8 ÷ 2": "4" }
        for (const text in answers) {
            const outcome = Calc.evaluate(text)
            ok("evaluates_" + text, outcome.ok && outcome.text === answers[text], outcome.text)
        }

        // Web search: the query is one URL-encoded parameter.
        const base = "https://duckduckgo.com/?q="
        ok("web_plain", Search.webSearchUrl("qml rice") === base + "qml%20rice", Search.webSearchUrl("qml rice"))
        ok("web_ampersand_hash", Search.webSearchUrl("a b&c#d") === base + "a%20b%26c%23d", Search.webSearchUrl("a b&c#d"))
        ok("web_question_slash", Search.webSearchUrl("a/b?c=d") === base + "a%2Fb%3Fc%3Dd", Search.webSearchUrl("a/b?c=d"))
        ok("web_unicode", Search.webSearchUrl("café") === base + "caf%C3%A9", Search.webSearchUrl("café"))
        ok("web_trimmed", Search.webSearchUrl("  hi  ") === base + "hi", Search.webSearchUrl("  hi  "))
        ok("web_empty", Search.webSearchUrl("") === base, Search.webSearchUrl(""))

        // "message <name>" / "call <name>": the intent parser and the rows it makes.
        const intentOf = q => JSON.stringify(Fmt.phoneIntent(q))
        ok("intent_message", intentOf("message maya") === '{"verb":"message","target":"maya"}', intentOf("message maya"))
        ok("intent_text_is_message", intentOf("Text  Maya ") === '{"verb":"message","target":"Maya"}', intentOf("Text  Maya "))
        ok("intent_call_case_insensitive", intentOf("CALL  Jon ") === '{"verb":"call","target":"Jon"}', intentOf("CALL  Jon "))
        ok("intent_needs_target", Fmt.phoneIntent("call") === null && Fmt.phoneIntent("message ") === null)
        ok("intent_needs_whole_word", Fmt.phoneIntent("messages maya") === null && Fmt.phoneIntent("hello message bob") === null)
        ok("intent_target_capped", Fmt.phoneIntent("message " + "x".repeat(65)) === null)
        ok("number_shapes", Fmt.looksLikeNumber("+15550001") && Fmt.looksLikeNumber("+44 7700 900123")
            && !Fmt.looksLikeNumber("maya") && !Fmt.looksLikeNumber("12") && !Fmt.looksLikeNumber("+1 555; rm"))
        ok("rows_none_when_disabled", Fmt.phoneRows(Fmt.phoneIntent("message maya"), [], false, true).length === 0)
        ok("rows_none_without_intent", Fmt.phoneRows(null, [], true, true).length === 0)
        const callOff = Fmt.phoneRows(Fmt.phoneIntent("call maya"), [], true, false)
        ok("call_off_is_disabled_row", callOff.length === 1 && callOff[0].enabled === false
            && callOff[0].executable === false && callOff[0].phoneVerb === undefined
            && callOff[0].subtitle.indexOf("Calls are off") === 0, JSON.stringify(callOff))
        const msgRows = Fmt.phoneRows(Fmt.phoneIntent("message maya"), [{ name: "Maya", number: "+15550001" }], true, false)
        ok("message_row_from_contact", msgRows.length === 1 && msgRows[0].title === "Message Maya"
            && msgRows[0].phoneVerb === "message" && msgRows[0].phoneNumber === "+15550001" && msgRows[0].enabled === true)
        const typed = Fmt.phoneRows(Fmt.phoneIntent("message +15559999"), [{ name: "Maya", number: "+15550001" }], true, true)
        ok("typed_number_row_first", typed.length === 2 && typed[0].phoneNumber === "+15559999"
            && typed[1].phoneName === "Maya")
        const many = Fmt.phoneRows(Fmt.phoneIntent("message ma"), [1, 2, 3, 4, 5].map(i => ({ name: "M" + i, number: "+1555000" + i })), true, true)
        ok("phone_rows_capped_at_4", many.length === 4)

        // The panel: phone rows lead the list, dial and compose go through the phone stand-in.
        const stubPalette = {
            revision: 0,
            search: (text, limit) => [],
            execute: (result, copy, newInstance) => ({ handled: true })
        }
        const stubPhone = {
            callsEnabled: false,
            dialled: [],
            composed: [],
            findContacts: (query, cb) => cb({ v: 1, ok: true, contacts: [{ name: "Maya", number: "+15550001" }] }),
            openCompose: (name, number) => stubPhone.composed.push(name + "|" + number),
            dial: (number, cb) => { stubPhone.dialled.push(number); cb({ v: 1, ok: true }) }
        }
        const panel = panelComponent.createObject(root, { provider: stubPalette, phone: stubPhone, phoneEnabled: true })
        let dismissals = 0
        panel.dismissRequested.connect(() => { dismissals++ })
        panel.text = "message maya"
        panel.lookupContacts()
        let rows = panel.results
        ok("panel_message_row_leads", rows.length === 1 && rows[0].phoneVerb === "message"
            && rows[0].title === "Message Maya", JSON.stringify(rows.map(r => r.title)))
        panel.currentIndex = 0
        panel.activateCurrent(false)
        ok("panel_message_opens_compose_not_send", stubPhone.composed.join() === "Maya|+15550001"
            && stubPhone.dialled.length === 0 && dismissals === 1, stubPhone.composed.join())

        panel.text = "call maya"
        panel.lookupContacts()
        rows = panel.results
        ok("panel_call_off_row_disabled", rows.length === 1 && rows[0].enabled === false, JSON.stringify(rows.map(r => r.enabled)))
        panel.currentIndex = 0
        panel.activateCurrent(false)
        ok("panel_call_off_never_dials", stubPhone.dialled.length === 0 && dismissals === 1)

        // Calls on: a second panel whose phone stand-in starts with calls enabled.
        const dialledOn = []
        const phoneOn = {
            callsEnabled: true,
            findContacts: stubPhone.findContacts,
            openCompose: () => {},
            dial: (number, cb) => { dialledOn.push(number); cb({ v: 1, ok: true }) }
        }
        const panelOn = panelComponent.createObject(root, { provider: stubPalette, phone: phoneOn, phoneEnabled: true })
        let dismissalsOn = 0
        panelOn.dismissRequested.connect(() => { dismissalsOn++ })
        panelOn.text = "call maya"
        panelOn.lookupContacts()
        rows = panelOn.results
        ok("panel_call_on_row_dials", rows.length === 1 && rows[0].phoneVerb === "call", JSON.stringify(rows.map(r => r.phoneVerb)))
        panelOn.currentIndex = 0
        panelOn.activateCurrent(false)
        ok("panel_call_on_dials_number", dialledOn.join() === "+15550001" && dismissalsOn === 1, dialledOn.join())

        panel.chipIndex = 0
        panel.text = "message maya"
        panel.lookupContacts()
        ok("chip_filter_hides_phone_rows", panel.results.length === 0)
        panel.chipIndex = -1
        panel.text = "notes"
        ok("plain_query_has_no_phone_rows", panel.results.length === 0)

        console.log("=== SPOTLIGHT TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.quit()
    }
}
