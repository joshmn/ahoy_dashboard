import assert from "node:assert/strict"
import test from "node:test"
import { FrameQueue } from "../../assets/javascript/runtime/frame_queue.js"

const flush = () => new Promise((resolve) => setImmediate(resolve))

const panel = (id, started) => {
  let finish
  let fail
  const response = new Promise((resolve, reject) => {
    finish = resolve
    fail = reject
  })

  return {
    id,
    isConnected: true,
    finish,
    fail,
    loadInitial() {
      started.push(id)
      return response
    },
  }
}

test("keeps at most two initial requests active while advancing the queue", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const first = panel("first", started)
  queue.add(first)
  queue.add(panel("second", started))
  queue.add(panel("third", started))
  await flush()
  const before = [...started]
  first.finish(true)
  await flush()

  assert.deepEqual([before, started], [["first", "second"], ["first", "second", "third"]])
})

test("starts the high priority summary before earlier ordinary frames", async () => {
  const queue = new FrameQueue(1)
  const started = []
  queue.add(panel("ordinary", started))
  queue.add(panel("summary", started), { priority: 1 })
  await flush()

  assert.deepEqual(started, ["summary"])
})

test("holds visible panels until their summary has settled", async () => {
  const queue = new FrameQueue(2)
  const started = []
  queue.add(panel("report", started), { after: "summary" })
  queue.add(panel("summary", started), { priority: 1 })
  await flush()

  assert.deepEqual(started, ["summary"])
})

test("releases dependent panels after a failed summary response", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const summary = panel("summary", started)
  queue.add(summary, { priority: 1 })
  queue.add(panel("report", started), { after: "summary" })
  await flush()
  summary.finish(false)
  await flush()

  assert.deepEqual(started, ["summary", "report"])
})

test("releases dependent panels when the summary loader rejects", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const summary = panel("summary", started)
  queue.add(summary)
  queue.add(panel("report", started), { after: "summary" })
  await flush()
  summary.fail(new Error("Connection failed"))
  await flush()

  assert.deepEqual(started, ["summary", "report"])
})

test("loads an offscreen panel only after it becomes nearby", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const report = panel("report", started)
  queue.complete("summary")
  queue.add(report, { after: "summary", visible: false })
  await flush()
  const before = [...started]
  queue.visibility(report, true)
  await flush()

  assert.deepEqual([before, started], [[], ["report"]])
})

test("does not start a panel that moved away before its dependency finished", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const report = panel("report", started)
  queue.add(report, { after: "summary", visible: true })
  queue.visibility(report, false)
  queue.complete("summary")
  await flush()

  assert.deepEqual(started, [])
})

test("removes cancelled queued panels without disturbing active work", async () => {
  const queue = new FrameQueue(1)
  const started = []
  const first = panel("first", started)
  const removed = panel("removed", started)
  queue.add(first)
  queue.add(removed)
  await flush()
  queue.cancel(removed)
  first.finish(true)
  await flush()

  assert.deepEqual(started, ["first"])
})

test("does not fetch disconnected frames", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const removed = panel("removed", started)
  queue.add(removed)
  removed.isConnected = false
  await flush()

  assert.deepEqual(started, [])
})

test("cancels work selected by the queue before its fetch begins", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const removed = panel("removed", started)
  queue.add(removed)
  await Promise.resolve()
  queue.cancel(removed)
  await flush()

  assert.deepEqual(started, [])
})

test("allows an explicit replacement request to settle a cancelled dependency", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const summary = panel("summary", started)
  queue.add(summary)
  queue.add(panel("report", started), { after: "summary" })
  await flush()
  queue.cancel(summary)
  summary.finish(null)
  await flush()
  const before = [...started]
  queue.complete("summary")
  await flush()

  assert.deepEqual([before, started], [["summary"], ["summary", "report"]])
})

test("drops navigation work and accepts restored-page requests after resume", async () => {
  const queue = new FrameQueue(2)
  const started = []
  const frame = panel("restored", started)
  queue.add(frame)
  queue.pause()
  await flush()
  const before = [...started]
  queue.resume()
  queue.add(frame)
  await flush()

  assert.deepEqual([before, started], [[], ["restored"]])
})
