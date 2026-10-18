import assert from "node:assert/strict"
import test from "node:test"
import { modified, wrap } from "../../assets/javascript/runtime/keys.js"

test("wrap starts at the top going down and at the bottom going up when nothing is marked", () => {
  assert.deepEqual([wrap(-1, 1, 5), wrap(-1, -1, 5)], [0, 4])
})

test("wrap goes round both ends", () => {
  assert.deepEqual([wrap(4, 1, 5), wrap(0, -1, 5)], [0, 4])
})

test("wrap steps through the middle", () => {
  assert.deepEqual([wrap(2, 1, 5), wrap(2, -1, 5)], [3, 1])
})

test("wrap stays put in a list of one", () => {
  assert.deepEqual([wrap(0, 1, 1), wrap(0, -1, 1), wrap(-1, -1, 1)], [0, 0, 0])
})

test("modified is true for any of the four modifier keys", () => {
  assert.deepEqual(
    [{ metaKey: true }, { ctrlKey: true }, { shiftKey: true }, { altKey: true }].map((event) => Boolean(modified(event))),
    [true, true, true, true]
  )
})

test("modified is false for a plain click or key", () => {
  assert.equal(Boolean(modified({ metaKey: false, ctrlKey: false, shiftKey: false, altKey: false })), false)
  assert.equal(Boolean(modified({})), false)
})
