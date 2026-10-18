import assert from "node:assert/strict"
import test from "node:test"
import { escapeHtml } from "../../assets/javascript/runtime/html.js"

test("escapeHtml escapes the five characters that matter in text and in quoted attributes", () => {
  assert.equal(escapeHtml(`<b class="x">Tom & Jerry's</b>`), "&lt;b class=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/b&gt;")
})

test("escapeHtml reads nothing as an empty string and anything else as text", () => {
  assert.deepEqual([escapeHtml(null), escapeHtml(undefined), escapeHtml(0), escapeHtml("plain")], ["", "", "0", "plain"])
})

test("escapeHtml treats text that looks escaped as text", () => {
  assert.equal(escapeHtml("&amp;"), "&amp;amp;")
})
