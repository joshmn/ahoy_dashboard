import assert from "node:assert/strict"
import test from "node:test"
import { counted, plural, sentence } from "../../assets/javascript/runtime/text.js"

test("sentence joins the way Rails' to_sentence does", () => {
  assert.deepEqual(
    [sentence([]), sentence(["visitors"]), sentence(["visitors", "pages"]), sentence(["visitors", "pages", "goals"])],
    ["", "visitors", "visitors and pages", "visitors, pages, and goals"]
  )
})

test("plural picks the word for the count, adding an s unless told otherwise", () => {
  assert.deepEqual(
    [plural(1, "page"), plural(0, "page"), plural(2, "page"), plural(1, "query", "queries"), plural(3, "query", "queries")],
    ["page", "pages", "pages", "query", "queries"]
  )
})

test("counted puts the delimited count in front of the word", () => {
  assert.deepEqual(
    [counted(1, "visitor"), counted(1234, "visitor"), counted(2, "search", "searches"), counted(0, "check")],
    ["1 visitor", "1,234 visitors", "2 searches", "0 checks"]
  )
})
