import assert from "node:assert/strict"
import test from "node:test"
import { CommandDialog } from "../../assets/javascript/runtime/command_dialog.js"

const classes = () => {
  const names = new Set()
  return { add: (name) => names.add(name), remove: (name) => names.delete(name), contains: (name) => names.has(name) }
}

const listeners = new Map()
globalThis.document = {
  body: { classList: classes() },
  addEventListener: (type, callback) => listeners.set(type, callback),
  removeEventListener: (type) => listeners.delete(type)
}

const row = ({ hidden = false } = {}) => ({
  hidden,
  clicks: 0,
  attributes: {},
  classList: classes(),
  setAttribute(name, value) { this.attributes[name] = value },
  scrollIntoView() {},
  click() { this.clicks += 1 }
})

class Dialog extends CommandDialog {
  constructor(rows) {
    super({}, "test")
    this.rows = rows
    this.panel = { hidden: true, classList: classes() }
    this.closed = 0
    this.keys = []
    this.seen = []
  }

  get hasPanelTarget() { return true }
  get panelTarget() { return this.panel }
  get itemTargets() { return this.rows }

  close() {
    this.closed += 1
    this.conceal()
  }

  keyed(event) { this.keys.push(event.key) }
  marked(current) { this.seen.push(current) }
}

const press = (dialog, key) => {
  const event = { key, prevented: false, preventDefault() { this.prevented = true } }
  dialog.key(event)
  return event
}

const opened = (rows) => {
  const dialog = new Dialog(rows)
  dialog.connect()
  dialog.reveal()
  return dialog
}

const marked = (rows) => rows.map((each) => each.classList.contains("act"))

const frame = (results) => {
  const loads = []
  return { loads, load: async (url) => { loads.push(url); return results.shift() } }
}

test("revealing and concealing set the hidden attribute, the open class and the page lock together", () => {
  const dialog = opened([row()])

  assert.deepEqual([dialog.isOpen, dialog.panel.classList.contains("open"), document.body.classList.contains("tm-lock")], [true, true, true])

  dialog.conceal()

  assert.deepEqual([dialog.isOpen, dialog.panel.classList.contains("open"), document.body.classList.contains("tm-lock")], [false, false, false])
})

test("the first row is marked once a frame load lands", async () => {
  const rows = [row(), row()]
  const dialog = opened(rows)

  await dialog.swap(frame([true]), "/telemetry/pickers?facet=country")

  assert.deepEqual([dialog.index, marked(rows), rows[0].attributes["aria-selected"]], [0, [true, false], "true"])
})

test("a load that a newer one replaced marks nothing", async () => {
  const rows = [row()]
  const dialog = opened(rows)

  await dialog.swap(frame([null]), "/telemetry/pickers?facet=country")

  assert.deepEqual([dialog.index, marked(rows)], [-1, [false]])
})

test("the frame is not fetched again for the url it already shows", async () => {
  const dialog = opened([row()])
  const panel = frame([true])

  await dialog.swap(panel, "/telemetry/pickers")
  await dialog.swap(panel, "/telemetry/pickers")

  assert.deepEqual(panel.loads, ["/telemetry/pickers"])
})

test("a failed load is tried again the next time", async () => {
  const dialog = opened([row()])
  const panel = frame([false, true])

  await dialog.swap(panel, "/telemetry/pickers")
  await dialog.swap(panel, "/telemetry/pickers")

  assert.deepEqual(panel.loads, ["/telemetry/pickers", "/telemetry/pickers"])
})

test("ArrowUp with nothing marked goes to the last row", () => {
  const rows = [row(), row(), row()]
  const dialog = opened(rows)

  const event = press(dialog, "ArrowUp")

  assert.deepEqual([event.prevented, dialog.index, marked(rows)], [true, 2, [false, false, true]])
})

test("ArrowDown goes round from the last row to the first, skipping hidden rows", () => {
  const rows = [row(), row({ hidden: true }), row()]
  const dialog = opened(rows)
  dialog.mark(1)

  press(dialog, "ArrowDown")

  assert.deepEqual([dialog.index, marked(rows)], [0, [true, false, false]])
})

test("Enter clicks the marked row and does nothing with none", () => {
  const rows = [row(), row()]
  const dialog = opened([])

  const missed = press(dialog, "Enter")
  dialog.rows = rows
  dialog.mark(1)
  const hit = press(dialog, "Enter")

  assert.deepEqual([missed.prevented, hit.prevented, rows.map((each) => each.clicks)], [false, true, [0, 1]])
})

test("Escape closes, and keys the dialog has no use for go to keyed", () => {
  const dialog = opened([row()])

  press(dialog, "ArrowLeft")
  press(dialog, "Escape")

  assert.deepEqual([dialog.keys, dialog.closed, dialog.isOpen], [["ArrowLeft"], 1, false])
})

test("keys are ignored while the dialog is shut", () => {
  const dialog = new Dialog([row()])
  dialog.connect()

  const event = press(dialog, "ArrowDown")

  assert.deepEqual([event.prevented, dialog.index, dialog.keys], [false, -1, []])
})

test("marked hears about the row that was marked, and about there being none", () => {
  const rows = [row()]
  const dialog = opened(rows)

  dialog.mark(0)
  dialog.rows = []
  dialog.mark(0)

  assert.deepEqual(dialog.seen, [rows[0], undefined])
})

test("disconnecting lets go of the keys and the page lock", () => {
  const dialog = opened([row()])

  dialog.disconnect()

  assert.deepEqual([listeners.has("keydown"), document.body.classList.contains("tm-lock")], [false, false])
})
