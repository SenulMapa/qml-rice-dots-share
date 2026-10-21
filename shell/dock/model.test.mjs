// Unit tests for shell/dock/model.js (a .pragma library QML module, loaded
// here through vm). Run: node --test shell/dock/model.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const src = readFileSync(path.join(here, "model.js"), "utf8").replace(/^\.pragma.*$/m, "");
const M = vm.runInNewContext(src + "\n({ nextAddress, focusCmd, restoreCmd, closeCmd })", {});

test("nextAddress cycles by focusHistoryID ascending-recency", () => {
    // focusHistoryID: 0 = focused. Cycling the focused app goes to the next most recent window.
    const ranks = { "0x1": 1, "0x2": 2, "0x3": 0 };
    assert.equal(M.nextAddress(["0x1", "0x2", "0x3"], "0x3", ranks), "0x1");
    assert.equal(M.nextAddress(["0x1", "0x2", "0x3"], "0x1", ranks), "0x2");
    assert.equal(M.nextAddress(["0x1", "0x2", "0x3"], "0x2", ranks), "0x3");
});

test("nextAddress wraps back to the focused window", () => {
    const ranks = { "0x1": 1, "0x2": 2, "0x3": 0 };
    assert.equal(M.nextAddress(["0x1", "0x2", "0x3"], "0x2", ranks), "0x3");
});

test("nextAddress from an unfocused app starts at its most recent window", () => {
    assert.equal(M.nextAddress(["0x2", "0x1"], "0x9", { "0x1": 3, "0x2": 1 }), "0x2");
});

test("nextAddress without ranks keeps address order", () => {
    assert.equal(M.nextAddress(["0x2", "0x1", "0x3"], "0x1"), "0x2");
    assert.equal(M.nextAddress(["0x2", "0x1", "0x3"], "0x3"), "0x1");
    assert.equal(M.nextAddress([], "0x1"), "");
});

test("nextAddress does not mutate its input", () => {
    const list = ["0x3", "0x1", "0x2"];
    M.nextAddress(list, "0x1", { "0x1": 0, "0x2": 1, "0x3": 2 });
    assert.deepEqual(list, ["0x3", "0x1", "0x2"]);
});
