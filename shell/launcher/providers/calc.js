.pragma library

// calc.js -- safe arithmetic for the launcher's "=" calculator.
//
// Hand-written recursive descent. No eval, no Function, no dynamic QML
// objects: the input is only ever tokenised and walked, never executed.
//
// Grammar, lowest precedence first:
//   expr    := term  (('+' | '-') term)*
//   term    := unary (('*' | '/' | '%') unary)*     also '×' and '÷'
//   unary   := ('-' | '+') unary | power           unary binds looser than '^'
//   power   := primary ('^' unary)?                right-associative
//   primary := number | constant | func '(' expr ')' | '(' expr ')'
//
// No implicit multiplication: "2pi" and "2(3)" are errors on purpose.
// Trig functions take radians.

var CONSTANTS = { pi: Math.PI, e: Math.E }
var FUNCTIONS = {
    sqrt: Math.sqrt,
    abs: Math.abs,
    sin: Math.sin,
    cos: Math.cos,
    tan: Math.tan,
    log: Math.log10,
    ln: Math.log,
    round: Math.round,
    floor: Math.floor,
    ceil: Math.ceil
}
var MAX_SOURCE_LENGTH = 200

function hasOwn(table, key) {
    return Object.prototype.hasOwnProperty.call(table, key)
}

function tokenize(source) {
    const tokens = []
    let i = 0
    while (i < source.length) {
        const ch = source[i]
        if (ch === " " || ch === "\t") {
            i += 1
            continue
        }
        const rest = source.slice(i)
        const number = /^(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(rest)
        if (number) {
            tokens.push({ type: "num", value: Number(number[0]) })
            i += number[0].length
            continue
        }
        const word = /^[A-Za-z_]+/.exec(rest)
        if (word) {
            tokens.push({ type: "name", value: word[0].toLowerCase() })
            i += word[0].length
            continue
        }
        if ("+-*/%^()".indexOf(ch) >= 0) {
            tokens.push({ type: "op", value: ch })
        } else if (ch === "×") {
            tokens.push({ type: "op", value: "*" })
        } else if (ch === "÷") {
            tokens.push({ type: "op", value: "/" })
        } else {
            throw new Error("Unexpected character")
        }
        i += 1
    }
    return tokens
}

function parse(tokens) {
    let pos = 0

    function isOp(value) {
        const token = tokens[pos]
        return token !== undefined && token.type === "op" && token.value === value
    }

    function expectOp(value) {
        if (!isOp(value))
            throw new Error("Expected " + value)
        pos += 1
    }

    function expr() {
        let value = term()
        while (isOp("+") || isOp("-")) {
            const op = tokens[pos].value
            pos += 1
            const rhs = term()
            value = op === "+" ? value + rhs : value - rhs
        }
        return value
    }

    function term() {
        let value = unary()
        while (isOp("*") || isOp("/") || isOp("%")) {
            const op = tokens[pos].value
            pos += 1
            const rhs = unary()
            if (op === "*")
                value = value * rhs
            else if (op === "/")
                value = value / rhs
            else
                value = value % rhs
        }
        return value
    }

    function unary() {
        if (isOp("-")) {
            pos += 1
            return -unary()
        }
        if (isOp("+")) {
            pos += 1
            return unary()
        }
        return power()
    }

    function power() {
        const base = primary()
        if (isOp("^")) {
            pos += 1
            return Math.pow(base, unary())
        }
        return base
    }

    function primary() {
        const token = tokens[pos]
        if (token === undefined)
            throw new Error("Unexpected end")
        if (token.type === "num") {
            pos += 1
            return token.value
        }
        if (token.type === "name") {
            pos += 1
            if (isOp("(")) {
                if (!hasOwn(FUNCTIONS, token.value))
                    throw new Error("Unknown function")
                pos += 1
                const argument = expr()
                expectOp(")")
                return FUNCTIONS[token.value](argument)
            }
            if (hasOwn(CONSTANTS, token.value))
                return CONSTANTS[token.value]
            throw new Error("Unknown name")
        }
        if (isOp("(")) {
            pos += 1
            const value = expr()
            expectOp(")")
            return value
        }
        throw new Error("Unexpected token")
    }

    const value = expr()
    if (pos !== tokens.length)
        throw new Error("Unexpected token")
    return value
}

// Up to 10 significant digits, trailing zeros trimmed, no thousands separators.
function formatResult(value) {
    if (Number.isNaN(value))
        return "Undefined"
    if (value === Infinity)
        return "∞"
    if (value === -Infinity)
        return "−∞"
    if (value === 0)
        return "0"
    return String(Number(value.toPrecision(10)))
}

// Never throws. Returns { ok, text, error }; text is the formatted answer.
function evaluate(source) {
    try {
        if (typeof source !== "string" || source.length > MAX_SOURCE_LENGTH)
            return { ok: false, text: "", error: "Expression too long" }
        const tokens = tokenize(source)
        if (tokens.length === 0)
            return { ok: false, text: "", error: "Empty expression" }
        const value = parse(tokens)
        return { ok: true, text: formatResult(value), error: "" }
    } catch (err) {
        return { ok: false, text: "", error: String(err && err.message ? err.message : err) }
    }
}

if (typeof module !== "undefined")
    module.exports = { evaluate: evaluate, formatResult: formatResult }
