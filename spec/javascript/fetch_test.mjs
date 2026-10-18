import assert from "node:assert/strict"
import test from "node:test"
import { getFragment, getJSON } from "../../assets/javascript/runtime/fetch.js"

test("getJSON asks for JSON, passes the signal on and returns the parsed body", async (context) => {
  const signal = new AbortController().signal
  const fetch = context.mock.method(globalThis, "fetch", async () => ({ ok: true, json: async () => ({ visitors: 4 }) }))

  assert.deepEqual(await getJSON("/telemetry/realtime", { signal }), { visitors: 4 })
  assert.deepEqual(fetch.mock.calls[0].arguments, ["/telemetry/realtime", { headers: { Accept: "application/json" }, signal }])
})

test("getJSON throws on a response that is not ok", async (context) => {
  context.mock.method(globalThis, "fetch", async () => ({ ok: false, status: 500, json: async () => ({}) }))

  await assert.rejects(getJSON("/telemetry/realtime"), { message: "500" })
})

test("getFragment names the frame it wants and sends the session", async (context) => {
  const signal = new AbortController().signal
  const fetch = context.mock.method(globalThis, "fetch", async () => ({ ok: true, redirected: false, text: async () => "<p>rows</p>" }))

  assert.equal(await getFragment("/telemetry/commands", { frame: "tm-palette-commands", signal }), "<p>rows</p>")
  assert.deepEqual(fetch.mock.calls[0].arguments, [
    "/telemetry/commands",
    { signal, credentials: "same-origin", headers: { Accept: "text/html", "Tm-Frame": "tm-palette-commands" } }
  ])
})

test("getFragment throws when the request was redirected", async (context) => {
  context.mock.method(globalThis, "fetch", async () => ({ ok: true, redirected: true, text: async () => "<form>Sign in</form>" }))

  await assert.rejects(getFragment("/telemetry/commands", { frame: "tm-palette-commands" }))
})

test("getFragment throws on a response that is not ok", async (context) => {
  context.mock.method(globalThis, "fetch", async () => ({ ok: false, redirected: false, text: async () => "" }))

  await assert.rejects(getFragment("/telemetry/filters", { frame: "tm-filter-controls" }))
})
