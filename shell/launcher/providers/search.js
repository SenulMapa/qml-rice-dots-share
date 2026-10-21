.pragma library

// search.js -- pure helpers for the Spotlight palette: arithmetic detection
// and the web-search URL. No Quickshell types, so test-spotlight.qml can load
// it directly.

var MAX_ARITHMETIC_LENGTH = 200
var MIN_FILE_QUERY = 2
var SEARCH_ENDPOINT = "https://duckduckgo.com/?q="

// Only the characters an arithmetic expression can use. Letters are left out
// on purpose: "sqrt(16)" and "pi" need the explicit "=" calculator.
var ARITHMETIC_CHARS = /^[0-9.\s+\-*/%^()×÷]+$/
// A binary operator must sit between two operands. That keeps a bare "-5",
// a bare "2024" and a lone "5%" out of the calculator, so they stay searches.
// A unary sign after the operator ("2^-1") is still allowed.
var BINARY_OPERATOR = /[0-9.)]\s*[-+*/%^×÷]\s*[-+]?\s*[0-9.(]/
// Date-shaped input ("2024-01-15", "1/2/2024") has the digits and operators of
// a subtraction or a division, so it would be evaluated. It is a search or a
// date, never a sum: both shapes are excluded here.
var ISO_DATE = /^\d{4}-\d{1,2}-\d{1,2}$/
var SLASH_DATE = /^\d{1,2}\/\d{1,2}\/\d{2,4}$/

// True when the text reads as arithmetic without the "=" prefix.
// This only checks the shape. The caller still has to evaluate it.
function isArithmetic(text) {
    const trimmed = (text || "").trim()
    return trimmed.length > 0
        && trimmed.length <= MAX_ARITHMETIC_LENGTH
        && ARITHMETIC_CHARS.test(trimmed)
        && /\d/.test(trimmed)
        && BINARY_OPERATOR.test(trimmed)
        && !ISO_DATE.test(trimmed)
        && !SLASH_DATE.test(trimmed)
}

// encodeURIComponent keeps the query in one parameter: "&", "#" and "?" in
// the typed text must not start a new parameter or a fragment.
function webSearchUrl(query) {
    return SEARCH_ENDPOINT + encodeURIComponent((query || "").trim())
}

if (typeof module !== "undefined")
    module.exports = {
        isArithmetic: isArithmetic,
        webSearchUrl: webSearchUrl,
        MIN_FILE_QUERY: MIN_FILE_QUERY
    }
