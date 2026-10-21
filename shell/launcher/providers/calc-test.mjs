// Node check for calc.js. Run: node shell/launcher/providers/calc-test.mjs
// calc.js starts with `.pragma library` (QML-only), so load it through vm
// after dropping that line. The guarded module.exports is what we read back.
import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import assert from "node:assert/strict"

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, "calc.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
runInNewContext(source, sandbox)
const { evaluate } = sandbox.module.exports

const cases = [
    ["2+3*4", "14"],
    ["2^3^2", "512"],
    ["-(3+1)*2", "-8"],
    ["sqrt(16)", "4"],
    ["10%3", "1"],
    ["1/0", "∞"],
    ["0.1+0.2", "0.3"],
    ["1e3", "1000"],
    ["2×3÷4", "1.5"],
    ["2^-1", "0.5"],
    ["-2^2", "-4"],
    ["pi", "3.141592654"],
    ["log(1000)", "3"],
    ["ln(e)", "1"],
    ["round(2.5)", "3"],
    ["1/3", "0.3333333333"],
    ["0/0", "Undefined"],
    ["sqrt(-1)", "Undefined"],
]
const invalid = ["", "2+", "foo", "2pi", "2(3)", "sqrt 16", "((1)", "1)", "2e", "toString(1)", "constructor"]

let failed = 0
function check(name, fn) {
    try {
        fn()
        console.log(`PASS ${name}`)
    } catch (err) {
        failed += 1
        console.log(`FAIL ${name}: ${err.message}`)
    }
}
for (const [input, expected] of cases) {
    check(`${input} = ${expected}`, () => {
        const outcome = evaluate(input)
        assert.equal(outcome.ok, true, outcome.error)
        assert.equal(outcome.text, expected)
    })
}
for (const input of invalid) {
    check(`invalid "${input}" is rejected without throwing`, () => {
        assert.equal(evaluate(input).ok, false)
    })
}
console.log(failed === 0 ? "=== calc-test: all passed ===" : `=== calc-test: ${failed} failed ===`)
process.exit(failed === 0 ? 0 : 1)
