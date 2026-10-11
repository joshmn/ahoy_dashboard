export class FrameQueue {
  constructor(limit = 2) {
    this.limit = limit
    this.waiting = new Map()
    this.active = new Map()
    this.settled = new Set()
    this.scheduled = false
    this.paused = false
  }

  add(frame, { priority = 0, after = null, visible = true } = {}) {
    this.waiting.set(frame, { priority, after, visible, cancelled: false })
    this.schedule()
  }

  visibility(frame, visible) {
    const entry = this.waiting.get(frame)
    if (!entry) return

    entry.visible = visible
    this.schedule()
  }

  cancel(frame) {
    this.waiting.delete(frame)
    const entry = this.active.get(frame)
    if (entry) entry.cancelled = true
  }

  complete(id) {
    if (id) this.settled.add(id)
    this.schedule()
  }

  pause() {
    this.paused = true
    this.waiting.clear()
    this.active.forEach((entry) => { entry.cancelled = true })
  }

  resume() {
    this.paused = false
    this.schedule()
  }

  schedule() {
    if (this.scheduled || this.paused) return

    this.scheduled = true
    queueMicrotask(() => {
      this.scheduled = false
      this.drain()
    })
  }

  drain() {
    if (this.paused) return

    const ready = Array.from(this.waiting).filter(([frame, entry]) =>
      frame.isConnected && entry.visible && !this.active.has(frame) &&
      (!entry.after || this.settled.has(entry.after))
    ).sort((left, right) => right[1].priority - left[1].priority)

    for (const [frame, entry] of ready) {
      if (this.active.size >= this.limit) break

      this.waiting.delete(frame)
      this.active.set(frame, entry)
      Promise.resolve().then(() => {
        if (entry.cancelled || !frame.isConnected) return null

        return frame.loadInitial()
      }).then((result) => {
        if (result !== null && !entry.cancelled) this.complete(frame.id)
      }).catch(() => {
        if (!entry.cancelled) this.complete(frame.id)
      }).finally(() => {
        if (this.active.get(frame) === entry) this.active.delete(frame)
        this.schedule()
      })
    }
  }
}
