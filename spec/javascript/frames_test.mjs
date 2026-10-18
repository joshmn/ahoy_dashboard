import assert from "node:assert/strict"
import test from "node:test"
import { deferred } from "./support/deferred.mjs"
import { installFrameDom } from "./support/frame_dom.mjs"

installFrameDom()
const { Frame } = await import("../../assets/javascript/runtime/frames.js")

const frame = () => {
  const element = new Frame()
  element.id = "report"
  element.textContent = "Loading report"
  return element
}

const response = (content, ok = true) => ({ ok, text: async () => `<tm-frame id="report">${content}</tm-frame>` })
const retryButton = (element) => element.children.flatMap((child) => child.children || []).find((child) => child.tagName === "BUTTON")

test("a late response body cannot replace a newer successful load", async (context) => {
  const oldBody = deferred()
  context.mock.method(globalThis, "fetch", async (url) => url === "/old"
    ? { ok: true, text: () => oldBody.promise }
    : response("Current report"))
  const element = frame()
  const oldLoad = element.load("/old")
  await Promise.resolve()
  await element.load("/current")
  oldBody.resolve('<tm-frame id="report">Old report</tm-frame>')
  await oldLoad

  assert.equal(element.textContent, "Current report")
})

test("an obsolete network failure cannot replace a newer successful load", async (context) => {
  const oldRequest = deferred()
  context.mock.method(globalThis, "fetch", (url) => url === "/old" ? oldRequest.promise : Promise.resolve(response("Current report")))
  const element = frame()
  const oldLoad = element.load("/old", { automatic: true })
  await element.load("/current")
  oldRequest.reject(new Error("Connection failed"))
  await oldLoad

  assert.equal(element.textContent, "Current report")
})

test("a missing response frame displays an actionable retry", async (context) => {
  context.mock.method(console, "warn", () => {})
  context.mock.method(globalThis, "fetch", async () => ({ ok: true, text: async () => "<main>Not the requested panel</main>" }))
  const element = frame()
  await element.load("/report", { automatic: true })

  assert.deepEqual([element.hasAttribute("failed"), retryButton(element)?.textContent], [true, "Try again"])
})

test("retrying a failed initial request replaces its error with the result", async (context) => {
  let calls = 0
  context.mock.method(console, "warn", () => {})
  context.mock.method(globalThis, "fetch", async () => {
    calls += 1
    if (calls === 1) throw new Error("Connection failed")
    return response("Loaded report")
  })
  const element = frame()
  await element.load("/report", { automatic: true })
  await retryButton(element).click()

  assert.deepEqual([element.textContent, element.hasAttribute("complete"), element.hasAttribute("failed")], ["Loaded report", true, false])
})

test("an HTTP error preserves the server explanation and adds a retry", async (context) => {
  context.mock.method(globalThis, "fetch", async () => response("Data could not be read. ", false))
  const element = frame()
  await element.load("/report", { automatic: true })

  assert.equal(element.textContent, "Data could not be read. This panel could not be loaded.Try again")
})

test("interactive validation responses do not gain an automatic retry", async (context) => {
  context.mock.method(globalThis, "fetch", async () => response("Please correct the form", false))
  const element = frame()
  await element.load("/form", { method: "POST", body: "value=invalid" })

  assert.equal(element.textContent, "Please correct the form")
})

test("removing a frame aborts its request and ignores a late response", async (context) => {
  const pending = deferred()
  let signal
  context.mock.method(globalThis, "fetch", (_url, options) => {
    signal = options.signal
    return pending.promise
  })
  const element = frame()
  const loading = element.load("/report", { automatic: true })
  element.isConnected = false
  element.disconnectedCallback()
  pending.resolve(response("Stale report"))
  await loading

  assert.deepEqual([signal.aborted, element.textContent], [true, "Loading report"])
})

test("an older request finishing does not clear the newer request's busy state", async (context) => {
  const old = deferred()
  const current = deferred()
  context.mock.method(globalThis, "fetch", (url) => url === "/old" ? old.promise : current.promise)
  const element = frame()
  const first = element.load("/old")
  const second = element.load("/current")
  old.resolve(response("Old report"))
  await first
  const busy = element.getAttribute("aria-busy")
  current.resolve(response("Current report"))
  await second

  assert.equal(busy, "true")
})
