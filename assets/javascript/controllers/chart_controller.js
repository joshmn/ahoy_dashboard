import { Controller } from "../runtime/controllers.js"
import { format, tick } from "../runtime/format.js"
import { escapeHtml } from "../runtime/html.js"
import { smoothPath, areaPath } from "../runtime/path.js"

const GEOMETRY = { height: 300, left: 46, right: 14, top: 16, bottom: 28 }
const ANNOTATION_COLOURS = { deploy: "#7d87ea", campaign: "#4fc08d", note: "#9099a3" }

const DOT_RADIUS = 4
const TICK_SPACING = 95
const WIDE_TICK_SPACING = 130
const TWEEN_MS = 340
const FADE_MS = 180
const RESIZE_MS = 60
const BRUSH_THRESHOLD = 4
const MINUTE_MS = 60000
const BUCKET_MINUTES = { minute: 1, five_minutes: 5, fifteen_minutes: 15, hour: 60 }
const TICK_MINUTES = [1, 2, 5, 10, 15, 30, 60, 120, 180, 240, 360, 720, 1440]
const DAY_MINUTES = 1440

const NICE = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]

let charts = 0

const CLOCK_TICK = { hour: "numeric", minute: "2-digit" }
const CLOCK_TIP = { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }

const DATES = {
  minute: CLOCK_TICK,
  five_minutes: CLOCK_TICK,
  fifteen_minutes: CLOCK_TICK,
  hour: { hour: "numeric" },
  day: { month: "short", day: "numeric" },
  week: { month: "short", day: "numeric" },
  month: { month: "short", year: "numeric" }
}

const ACROSS_DAYS = {
  minute: { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" },
  hour: { month: "short", day: "numeric", hour: "numeric" }
}

const TIPS = {
  minute: CLOCK_TIP,
  five_minutes: CLOCK_TIP,
  fifteen_minutes: CLOCK_TIP,
  hour: { weekday: "short", month: "short", day: "numeric", hour: "numeric" },
  day: { weekday: "short", month: "short", day: "numeric" },
  week: { month: "short", day: "numeric" },
  month: { month: "short", year: "numeric" }
}

const clamp = (v, a, b) => Math.min(b, Math.max(a, v))

function niceCeil(value) {
  if (!(value > 0)) return 1

  const power = Math.pow(10, Math.floor(Math.log10(value)))
  const hit = NICE.find((m) => m * power >= value)

  return hit ? hit * power : 10 * power
}

const stamps = new Map()

function stamp(map, interval, time) {
  const key = map[interval] ? interval : "day"
  const id = `${map === TIPS ? "tip" : map === ACROSS_DAYS ? "across" : "tick"}:${key}`

  if (!stamps.has(id)) stamps.set(id, new Intl.DateTimeFormat("en-US", { ...map[key], timeZone: "UTC" }))

  const text = stamps.get(id).format(time)

  return map === TIPS && key === "week" ? `Week of ${text}` : text
}

const SPANS = {
  full: new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" }),
  short: new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" }),
  month: new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric", timeZone: "UTC" })
}

const dayOf = (key) => String(key).slice(0, 10)

function utc(day) {
  const [year, month, date] = day.split("-").map(Number)
  return new Date(Date.UTC(year, month - 1, date))
}

const isoDay = (date) => date.toISOString().slice(0, 10)

function addDays(day, count) {
  const date = utc(day)
  date.setUTCDate(date.getUTCDate() + count)
  return isoDay(date)
}

function monthEnd(day) {
  const date = utc(day)
  return isoDay(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)))
}

const WALL_CLOCK = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/

function wallClock(key) {
  const match = WALL_CLOCK.exec(String(key ?? ""))
  if (!match) return new Date(key)

  const [, year, month, day, hour = "0", minute = "0"] = match
  return new Date(Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute)))
}

const minuteOf = (key) => String(key).slice(0, 16)

function momentAt(text) {
  const date = utc(text.slice(0, 10))
  date.setUTCHours(Number(text.slice(11, 13)), Number(text.slice(14, 16)))
  return date
}

const addMinutes = (text, count) => new Date(momentAt(text).getTime() + count * MINUTE_MS).toISOString().slice(0, 16)

const midnight = (date) => date.getUTCHours() === 0 && date.getUTCMinutes() === 0

function clock(date) {
  if (midnight(date)) return "midnight"

  const hour = date.getUTCHours()
  const minute = date.getUTCMinutes()
  const minutes = minute ? `:${String(minute).padStart(2, "0")}` : ""

  return `${hour % 12 || 12}${minutes} ${hour < 12 ? "AM" : "PM"}`
}

function timeLabel(from, to) {
  const start = momentAt(from)
  const stop = momentAt(to)
  const opening = `${SPANS.short.format(start)}, ${clock(start)}`
  const sameDay = isoDay(stop) === isoDay(start) || (midnight(stop) && addDays(isoDay(start), 1) === isoDay(stop))

  return sameDay ? `${opening} to ${clock(stop)}` : `${opening} to ${SPANS.short.format(stop)}, ${clock(stop)}`
}

function spanLabel(from, to) {
  if (from === to) return SPANS.full.format(utc(from))
  if (from.endsWith("-01") && to === monthEnd(from)) return SPANS.month.format(utc(from))
  if (from.slice(0, 4) === to.slice(0, 4)) return `${SPANS.short.format(utc(from))} to ${SPANS.short.format(utc(to))}`

  return `${SPANS.full.format(utc(from))} to ${SPANS.full.format(utc(to))}`
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    data: Array,
    options: Object,
    height: { type: Number, default: GEOMETRY.height }
  }

  connect() {
    this.uid = `tm-chart-${++charts}`
    this.stillness = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.frame = 0
    this.first = true
    this.previous = null
    this.drag = null
    this.config = this.hasOptionsValue ? this.optionsValue : {}
    this.onBrushKey = (event) => { if (event.key === "Escape") this.endBrush() }

    this.build()
    this.watch()
    this.draw()
  }

  disconnect() {
    this.endBrush()
    cancelAnimationFrame(this.frame)
    clearTimeout(this.resizeTimer)
    this.observer?.disconnect()
    this.svg?.remove()
    this.tip?.remove()
    this.annoTip?.remove()
    this.table?.remove()
    this.svg = null
    this.tip = null
    this.annoTip = null
    this.table = null
  }

  update(data, options = null) {
    if (!this.svg || !data) return false

    if (options) this.optionsValue = options
    this.dataValue = data
    this.draw()

    return true
  }

  export(event) {
    event?.preventDefault()

    const { primary, comparison } = this.series
    const rows = primary?.data || []
    if (rows.length === 0) return

    const shadows = comparison?.data || []
    const header = ["date", this.label.toLowerCase().replace(/ /g, "_")]
    if (shadows.length === rows.length) header.push("previous")

    const lines = [header.join(",")]

    const cell = (value) => (value == null ? "" : Math.round(Number(value) * 100) / 100)

    rows.forEach(([time, value], i) => {
      const cells = [String(time), cell(value)]
      if (shadows.length === rows.length) cells.push(cell(shadows[i][1]))
      lines.push(cells.join(","))
    })

    const url = URL.createObjectURL(new Blob([lines.join("\n")], { type: "text/csv" }))
    const link = document.createElement("a")

    link.href = url
    link.download = `ahoy-dashboard-${this.label.toLowerCase().replace(/ /g, "-")}-${this.interval}.csv`
    link.click()

    URL.revokeObjectURL(url)
  }

  build() {
    this.host = this.hasCanvasTarget ? this.canvasTarget : this.element
    this.placeholder = this.host.querySelector(".empty")
    this.host.replaceChildren()
    if (this.placeholder) this.host.appendChild(this.placeholder)

    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    this.svg.setAttribute("height", this.geometry.height)
    this.svg.setAttribute("role", "img")
    this.host.appendChild(this.svg)

    this.table = document.createElement("div")
    this.table.className = "visually-hidden"
    this.host.appendChild(this.table)

    this.tip = document.createElement("div")
    this.tip.className = "tip"
    this.tip.hidden = true
    this.host.appendChild(this.tip)

    this.annoTip = document.createElement("div")
    this.annoTip.className = "tip anno-tip"
    this.annoTip.hidden = true
    this.host.appendChild(this.annoTip)
  }

  watch() {
    this.observer = new ResizeObserver(() => {
      if (this.host.clientWidth === this.drawnWidth) return

      clearTimeout(this.resizeTimer)
      this.resizeTimer = setTimeout(() => this.draw(), RESIZE_MS)
    })
    this.observer.observe(this.host)
  }

  get geometry() {
    return { ...GEOMETRY, height: this.heightValue }
  }

  get still() {
    return this.stillness?.matches
  }

  get options() {
    return this.config
  }

  get plugin() {
    return this.options?.library?.plugins?.tmFormat || {}
  }

  get label() {
    return this.plugin.label || "Visitors"
  }

  get type() {
    return this.plugin.value || "integer"
  }

  get interval() {
    return this.plugin.interval || "day"
  }

  get missing() {
    return this.plugin.missing || "No reading"
  }

  get ceiling() {
    return this.options?.library?.scales?.y?.max
  }

  get floor() {
    return this.options?.library?.scales?.y?.min ?? 0
  }

  get reversed() {
    return this.options?.library?.scales?.y?.reverse === true
  }

  get stroke() {
    return this.options?.library?.tmStroke || null
  }

  get filled() {
    return this.options?.library?.tmFill !== false
  }

  get selection() {
    const spec = this.options?.library?.plugins?.tmSelect
    return spec?.url && spec.from && spec.to ? spec : null
  }

  get series() {
    const all = this.hasDataValue ? this.dataValue : []

    return {
      primary: all[0] || null,
      comparison: all[1] || null
    }
  }

  draw() {
    this.config = this.hasOptionsValue ? this.optionsValue : {}
    const { primary, comparison } = this.series
    const rows = primary?.data || []
    if (this.placeholder) this.placeholder.hidden = rows.length > 0
    if (this.svg) this.svg.style.display = rows.length > 0 ? "" : "none"
    if (this.table) this.table.hidden = rows.length === 0
    if (!this.svg || rows.length === 0) return

    this.svg.setAttribute("aria-label", `${this.label} over time, listed in the table after this chart`)

    this.endBrush()

    this.drawnWidth = this.host.clientWidth
    const width = Math.max(320, this.drawnWidth - 10)
    const { height: H, left: pl, right: pr, top: pt, bottom: pb } = this.geometry
    const n = rows.length

    const keys = rows.map(([t]) => t)
    const times = keys.map((t) => wallClock(t))
    const values = rows.map(([, v]) => (v == null ? null : Number(v) || 0))
    const shadows = (comparison?.data || []).map(([, v]) => Number(v) || 0)
    const present = values.filter((v) => v != null)

    const peak = Math.max(...present, ...shadows, 0)
    const trough = present.length || shadows.length ? Math.min(...present, ...shadows) : 0
    const banded = this.floor > 0 || this.reversed
    const band = banded ? this.band(trough, peak) : null
    const min = band ? band.min : 0
    const max = band ? band.max : (this.ceiling != null ? this.ceiling : this.roof(peak))

    const span = max - min || 1
    const first = times[0].getTime()
    const length = times[n - 1].getTime() - first
    const timed = this.plugin.scale === "time" && n > 1 && length > 0
    const X = (i) => {
      const share = timed ? (times[i].getTime() - first) / length : n === 1 ? 0.5 : i / (n - 1)
      return pl + (width - pl - pr) * share
    }
    const Y = (v) => {
      const share = (v - min) / span
      return pt + (H - pt - pb) * (this.reversed ? share : 1 - share)
    }
    const baseY = Y(this.reversed ? max : min)
    const partial = this.plugin.partial === true && n > 1
    const split = partial ? X(n - 2) : 0
    const strokeStyle = this.stroke ? ` style="stroke:${this.stroke}"` : ""

    const geometry = { width, H, pl, pr, pt, pb, n, X, Y, baseY, max, min, partial, timed }
    const toPoints = (arr) => arr.map((v, i) => [X(i), Y(v)])

    const { line, area, lone } = this.trace(values, geometry)
    const shadow = shadows.length === n ? smoothPath(toPoints(shadows)) : ""

    const selectable = Boolean(this.selection)

    this.svg.setAttribute("viewBox", `0 0 ${width} ${H}`)
    this.svg.setAttribute("width", width)
    this.svg.classList.toggle("is-brushable", selectable)
    this.svg.innerHTML =
      this.defs(partial ? { split, width, H } : null) +
      this.bands(times, geometry) +
      this.grid(geometry) +
      (selectable ? `<rect class="brush" id="brush" y="${pt}" height="${(baseY - pt).toFixed(1)}" style="display:none"/>` : "") +
      this.labels(times, geometry) +
      (this.filled ? `<path id="marea" d="${area}" fill="url(#ga)"/>` : "") +
      (shadow ? `<path class="prev" id="pline" d="${shadow}"/>` : "") +
      `<path class="line" id="mline" d="${line}"${partial ? ` clip-path="url(#${this.uid}-done)"` : ""}${strokeStyle}/>` +
      (partial ? `<path class="line line--open" id="mopen" d="${line}" clip-path="url(#${this.uid}-open)"${strokeStyle}/>` : "") +
      `<g id="mlone">${lone}</g>` +
      `<line class="xh" id="xh" y1="${pt}" y2="${baseY}" style="display:none"/>` +
      `<circle class="dot" id="cdot" r="${DOT_RADIUS}" style="display:none"/>` +
      `<rect id="hz" x="${pl}" y="0" width="${width - pl - pr}" height="${H}" fill="transparent"/>` +
      this.annotations(times, geometry)

    if (this.table) this.table.innerHTML = this.tableHtml(times, values, shadows, partial)

    this.animate({ values, shadows, geometry, toPoints })
    this.hover({ times, values, shadows, geometry })
    this.brush({ keys, geometry })
    this.flags(geometry)

    this.previous = { key: this.shapeKey(values), width, values, shadows }
    this.first = false
  }

  shapeKey(values) {
    const gaps = values.map((v) => (v == null ? "0" : "1")).join("")
    return `${this.label}|${this.interval}|${values.length}|${gaps}`
  }

  trace(values, geometry) {
    const { X, Y, baseY } = geometry
    const runs = []
    let run = []

    values.forEach((v, i) => {
      if (v == null) {
        if (run.length) runs.push(run)
        run = []
      } else {
        run.push([X(i), Y(v)])
      }
    })
    if (run.length) runs.push(run)

    const lines = runs.map((points) => smoothPath(points))
    const fill = this.stroke ? ` style="fill:${this.stroke}"` : ""

    return {
      line: lines.join(""),
      area: runs.map((points, i) => (points.length > 1 ? areaPath(lines[i], points, baseY) : "")).join(""),
      lone: runs
        .filter((points) => points.length === 1)
        .map(([[x, y]]) => `<circle class="dot" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${DOT_RADIUS - 1}"${fill}/>`)
        .join("")
    }
  }

  band(trough, peak) {
    const pad = Math.max((peak - trough) * 0.25, 0.2)

    if (!this.type || this.type === "integer") {
      const min = Math.max(this.reversed ? 1 : 0, Math.floor(trough - pad))
      const span = Math.max(4, Math.ceil((Math.ceil(peak + pad) - min) / 4) * 4)

      return { min, max: min + span }
    }

    const min = Math.max(0, Math.floor((trough - pad) * 10) / 10)
    const max = Math.ceil((peak + pad) * 10) / 10

    return { min, max: max > min ? max : min + 1 }
  }

  roof(peak) {
    const nice = niceCeil(peak * 1.06 || 1)
    const whole = !this.type || this.type === "integer"

    return whole ? Math.ceil(nice / 4) * 4 : nice
  }

  defs(clip) {
    const clips = clip
      ? `<clipPath id="${this.uid}-done"><rect x="0" y="0" width="${clip.split.toFixed(1)}" height="${clip.H}"/></clipPath>` +
        `<clipPath id="${this.uid}-open"><rect x="${clip.split.toFixed(1)}" y="0" ` +
        `width="${(clip.width - clip.split).toFixed(1)}" height="${clip.H}"/></clipPath>`
      : ""

    return (
      '<defs><linearGradient id="ga" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="#5e6ad2" stop-opacity=".26"/>' +
      '<stop offset="1" stop-color="#5e6ad2" stop-opacity="0"/>' +
      `</linearGradient>${clips}</defs>`
    )
  }

  bands(times, geometry) {
    if (this.interval !== "day") return ""

    const { pt, baseY, n } = geometry
    let out = ""

    for (let i = 0; i < n; i++) {
      const day = times[i].getUTCDay()
      if (day !== 0 && day !== 6) continue

      const [from, to] = this.edges(i, geometry)

      out +=
        `<rect x="${from.toFixed(1)}" y="${pt}" width="${(to - from).toFixed(1)}" ` +
        `height="${(baseY - pt).toFixed(1)}" fill="rgba(255,255,255,.018)"/>`
    }

    return out
  }

  grid({ pl, pr, width, Y, baseY, max, min }) {
    let out = ""
    const floor = min ?? 0
    const first = floor > 0 ? 0 : 1

    for (let k = first; k <= 4; k++) {
      const y = Y(floor + (((max - floor) * k) / 4))
      out += `<line class="gl" x1="${pl}" x2="${width - pr}" y1="${y}" y2="${y}"/>`
    }

    return `${out}<line class="gl base" x1="${pl}" x2="${width - pr}" y1="${baseY}" y2="${baseY}"/>`
  }

  annotations(times, { pt, baseY, X, n }) {
    const notes = this.options?.library?.plugins?.tmAnnotations
    if (!Array.isArray(notes) || notes.length === 0 || n === 0) return ""

    const starts = times.map((time) => time.getTime())

    return notes.map((note) => {
      const at = wallClock(String(note.at ?? "")).getTime()
      if (Number.isNaN(at)) return ""

      let index = 0
      starts.forEach((start, candidate) => { if (start <= at) index = candidate })

      const colour = ANNOTATION_COLOURS[note.kind] || ANNOTATION_COLOURS.note
      const x = X(index)
      const at1 = x.toFixed(1)

      return `<g class="anno-hit" data-anno-label="${escapeHtml(note.label)}"` +
        ` data-anno-when="${escapeHtml(note.when_label || "")}"` +
        ` data-anno-kind="${escapeHtml(note.kind_label || "")}" data-x="${at1}">` +
        `<line class="anno-line" stroke="${colour}" x1="${at1}" x2="${at1}" y1="${pt + 13}" y2="${baseY}"/>` +
        `<path class="anno-flag" fill="${colour}" d="M${at1} ${pt + 12}V${pt + 1}h5.4l-1.7 2.6 1.7 2.6H${at1}Z"/>` +
        `<rect class="anno-tap" x="${(x - 8).toFixed(1)}" y="${pt - 3}" width="17" height="19" rx="3"/></g>`
    }).join("")
  }

  labels(times, { pl, pr, width, H, Y, max, min, n, X, timed }) {
    let out = ""

    for (let k = 0; k <= 4; k++) {
      const value = (min ?? 0) + (((max - (min ?? 0)) * k) / 4)
      out += `<text class="yl" x="${pl - 9}" y="${(Y(value) + 3.5).toFixed(1)}">${escapeHtml(tick(value, this.type))}</text>`
    }

    const across = Boolean(BUCKET_MINUTES[this.interval]) && n > 1 && isoDay(times[0]) !== isoDay(times[n - 1])
    const formats = across ? ACROSS_DAYS : DATES
    const key = across && this.interval !== "hour" ? "minute" : this.interval
    const spacing = across ? WIDE_TICK_SPACING : TICK_SPACING
    const room = Math.max(2, Math.min(n, Math.floor((width - 80) / spacing)))
    const shown = timed ? this.spaced(n, X, spacing) : this.stepped(times, n, room)

    shown.forEach((i) => {
      const x = X(i)
      const anchor = n > 1 && i === n - 1 ? ' style="text-anchor:end"' : x - pl < 28 ? ' style="text-anchor:start"' : ""
      out += `<text class="xl" x="${x}" y="${H - 9}"${anchor}>${escapeHtml(stamp(formats, key, times[i]))}</text>`
    })

    return out
  }

  stepped(times, n, room) {
    const { first, step } = this.ticks(times, n, room)
    const shown = []

    for (let i = first; i >= 0; i -= step) shown.push(i)

    return shown
  }

  spaced(n, X, spacing) {
    const shown = [n - 1]

    for (let i = n - 2; i >= 0; i--) {
      if (X(shown[shown.length - 1]) - X(i) >= spacing) shown.push(i)
    }

    return shown
  }

  ticks(times, n, room) {
    const plain = n > 1 ? Math.max(1, Math.ceil((n - 1) / (room - 1))) : 1
    const size = BUCKET_MINUTES[this.interval]
    if (!size || n < 2) return { first: n - 1, step: plain }

    const wanted = plain * size
    const every =
      wanted > DAY_MINUTES
        ? Math.ceil(wanted / DAY_MINUTES) * DAY_MINUTES
        : TICK_MINUTES.find((minutes) => minutes >= wanted && minutes % size === 0)
    const aligned = (time) => ((time.getUTCHours() * 60 + time.getUTCMinutes()) % Math.min(every, DAY_MINUTES)) === 0

    let first = n - 1
    while (first > 0 && !aligned(times[first])) first -= 1

    return { first: aligned(times[first]) ? first : n - 1, step: every / size }
  }

  animate({ values, shadows, geometry, toPoints }) {
    cancelAnimationFrame(this.frame)
    if (this.still) return

    const key = this.shapeKey(values)
    const old = this.previous

    if (this.first) return

    const tweenable =
      old && old.key === key && old.width === geometry.width && old.values.length === values.length

    if (!tweenable) return this.crossfade()

    const from = old.values
    const fromShadow = old.shadows.length === shadows.length ? old.shadows : null
    const lineEl = this.svg.querySelector("#mline")
    const areaEl = this.svg.querySelector("#marea")
    const openEl = this.svg.querySelector("#mopen")
    const prevEl = this.svg.querySelector("#pline")
    const loneEl = this.svg.querySelector("#mlone")
    const started = performance.now()

    const step = (now) => {
      const p = Math.min(1, (now - started) / TWEEN_MS)
      const e = 1 - Math.pow(1 - p, 3)
      const lerped = values.map((v, i) => (v == null ? null : from[i] + (v - from[i]) * e))
      const { line, area, lone } = this.trace(lerped, geometry)

      lineEl.setAttribute("d", line)
      openEl?.setAttribute("d", line)
      areaEl?.setAttribute("d", area)
      if (loneEl) loneEl.innerHTML = lone

      if (prevEl && fromShadow) {
        const shade = shadows.map((v, i) => fromShadow[i] + (v - fromShadow[i]) * e)
        prevEl.setAttribute("d", smoothPath(toPoints(shade)))
      }

      if (p < 1) this.frame = requestAnimationFrame(step)
    }

    this.frame = requestAnimationFrame(step)
  }

  crossfade() {
    this.svg.style.transition = "none"
    this.svg.style.opacity = "0"

    requestAnimationFrame(() => {
      this.svg.style.transition = `opacity ${FADE_MS}ms ease`
      this.svg.style.opacity = "1"
    })
  }

  flags({ width }) {
    if (!this.annoTip) return

    this.svg.querySelectorAll(".anno-hit").forEach((flag) => {
      const when = flag.dataset.annoWhen || ""

      const show = () => {
        const box = this.svg.getBoundingClientRect()
        const colour = flag.querySelector(".anno-flag")?.getAttribute("fill") || ""

        this.annoTip.innerHTML =
          `<div class="ak" style="color:${escapeHtml(colour)}">` +
          `<span class="adot" style="background:${escapeHtml(colour)}"></span>${escapeHtml(flag.dataset.annoKind)}</div>` +
          `<div class="anno-lbl">${escapeHtml(flag.dataset.annoLabel)}</div>` +
          (when ? `<div class="anno-when">${escapeHtml(when)}</div>` : "")
        this.annoTip.hidden = false

        const scale = box.width / width
        const x = Number(flag.dataset.x) * scale
        const wide = this.annoTip.offsetWidth
        let left = x + 12
        if (left + wide > box.width - 8) left = x - wide - 12

        this.annoTip.style.left = `${Math.max(4, left)}px`
        this.annoTip.style.top = "6px"
      }

      const hide = () => { this.annoTip.hidden = true }

      flag.addEventListener("pointerenter", show)
      flag.addEventListener("pointerleave", hide)
      const tap = flag.querySelector(".anno-tap")
      if (!tap) return

      tap.setAttribute("tabindex", "0")
      tap.setAttribute("role", "img")
      tap.setAttribute(
        "aria-label",
        `${flag.dataset.annoKind || "Note"}: ${flag.dataset.annoLabel || ""}${when ? `, ${when}` : ""}`
      )
      tap.addEventListener("focus", show)
      tap.addEventListener("blur", hide)
    })
  }

  hover({ times, values, shadows, geometry }) {
    const hit = this.svg.querySelector("#hz")
    const cross = this.svg.querySelector("#xh")
    const mark = this.svg.querySelector("#cdot")
    const { width, n, X, Y, partial } = geometry

    hit.addEventListener("pointermove", (event) => {
      const box = this.svg.getBoundingClientRect()
      const i = this.indexAt(event, geometry)
      const x = X(i)
      const gap = values[i] == null
      const y = gap ? geometry.pt + (geometry.baseY - geometry.pt) / 2 : Y(values[i])

      cross.setAttribute("x1", x)
      cross.setAttribute("x2", x)
      cross.style.display = ""
      mark.setAttribute("cx", x)
      mark.setAttribute("cy", y)
      mark.style.display = gap ? "none" : ""

      const range = this.drag ? this.extend(i, event) : null

      this.tip.innerHTML = range
        ? this.rangeTipHtml(range)
        : this.tipHtml(times[i], values[i], shadows[i], partial && i === n - 1)
      this.tip.hidden = false

      const scale = box.width / width
      const wide = this.tip.offsetWidth
      let left = x * scale + 14
      if (left + wide > box.width - 8) left = x * scale - wide - 14

      this.tip.style.left = `${Math.max(4, left)}px`
      this.tip.style.top = `${clamp(y * scale - 60, 6, box.height - 120)}px`
    })

    hit.addEventListener("pointerleave", () => {
      if (this.drag) return

      this.tip.hidden = true
      cross.style.display = "none"
      mark.style.display = "none"
    })
  }

  indexAt(event, { width, pl, pr, n, X, timed }) {
    const box = this.svg.getBoundingClientRect()
    const px = (event.clientX - box.left) * (width / box.width)

    if (!timed) return clamp(Math.round(((px - pl) / (width - pl - pr)) * (n - 1)), 0, n - 1)

    let nearest = 0
    for (let i = 1; i < n; i++) {
      if (Math.abs(X(i) - px) < Math.abs(X(nearest) - px)) nearest = i
    }

    return nearest
  }

  edges(i, { pl, pr, width, n, X }) {
    return [i ? (X(i - 1) + X(i)) / 2 : pl, i < n - 1 ? (X(i) + X(i + 1)) / 2 : width - pr]
  }

  brush({ keys, geometry }) {
    const spec = this.selection
    const hit = this.svg.querySelector("#hz")
    const band = this.svg.querySelector("#brush")
    if (!spec || !hit || !band) return

    hit.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || !event.isPrimary) return

      event.preventDefault()
      hit.setPointerCapture(event.pointerId)

      const i = this.indexAt(event, geometry)
      this.drag = { spec, keys, geometry, band, anchor: i, reach: i, x: event.clientX, moved: false }
      window.addEventListener("keydown", this.onBrushKey)
    })

    hit.addEventListener("pointerup", () => {
      const drag = this.drag
      if (!drag) return

      const range = drag.moved ? this.span(drag) : null
      if (!range || range.whole) return this.endBrush()

      this.endBrush({ keep: true })
      this.apply(drag.spec, range)
    })

    hit.addEventListener("pointercancel", () => this.endBrush())
    hit.addEventListener("lostpointercapture", () => this.endBrush())
  }

  extend(i, event) {
    const drag = this.drag
    drag.reach = i

    if (Math.abs(event.clientX - drag.x) >= BRUSH_THRESHOLD) drag.moved = true
    if (!drag.moved) return null

    const [left] = this.edges(Math.min(drag.anchor, i), drag.geometry)
    const [, right] = this.edges(Math.max(drag.anchor, i), drag.geometry)

    drag.band.setAttribute("x", left.toFixed(1))
    drag.band.setAttribute("width", (right - left).toFixed(1))
    drag.band.style.display = ""

    return this.span(drag)
  }

  endBrush({ keep = false } = {}) {
    const drag = this.drag
    if (!drag) return

    this.drag = null
    window.removeEventListener("keydown", this.onBrushKey)

    if (keep || !drag.moved) return

    drag.band.style.display = "none"
    if (this.tip) this.tip.hidden = true
  }

  span({ spec, keys, anchor, reach }) {
    const first = Math.min(anchor, reach)
    const last = Math.max(anchor, reach)
    const size = BUCKET_MINUTES[this.interval]
    if (size) return this.moments(keys, first, last, size)

    const start = dayOf(keys[first])
    const finish = this.lastDay(dayOf(keys[last]))
    const from = start < spec.from ? spec.from : start
    const to = finish > spec.to ? spec.to : finish

    return { from, to, label: spanLabel(from, to), whole: from === spec.from && to === spec.to }
  }

  moments(keys, first, last, size) {
    const from = minuteOf(keys[first])
    const to = addMinutes(minuteOf(keys[last]), size)
    const whole = first === 0 && last === keys.length - 1

    if (from.endsWith("T00:00") && to.endsWith("T00:00")) {
      const fromDay = from.slice(0, 10)
      const toDay = addDays(to.slice(0, 10), -1)

      return { from: fromDay, to: toDay, label: spanLabel(fromDay, toDay), whole }
    }

    return { from, to, label: timeLabel(from, to), whole }
  }

  lastDay(day) {
    if (this.interval === "week") return addDays(day, 6)
    if (this.interval === "month") return monthEnd(day)

    return day
  }

  apply(spec, range) {
    const url = new URL(spec.url, window.location.origin)

    url.searchParams.set("from", range.from)
    url.searchParams.set("to", range.to)
    url.searchParams.delete("interval")

    window.location.assign(url.pathname + url.search)
  }

  tableHtml(times, values, shadows, partial) {
    const compared = shadows.length === values.length
    const rows = values.map((value, i) => {
      const cells = [`<th scope="row">${escapeHtml(stamp(TIPS, this.interval, times[i]))}${partial && i === values.length - 1 ? " so far" : ""}</th>`,
        `<td>${escapeHtml(this.reading(value))}</td>`]
      if (compared) cells.push(`<td>${escapeHtml(format(shadows[i], this.type))}</td>`)
      return `<tr>${cells.join("")}</tr>`
    })

    return `<table><caption>${escapeHtml(this.label)} by ${escapeHtml(this.interval.replaceAll("_", " "))}</caption>` +
      `<thead><tr><th scope="col">When</th><th scope="col">${escapeHtml(this.label)}</th>` +
      `${compared ? '<th scope="col">Previous period</th>' : ""}</tr></thead>` +
      `<tbody>${rows.join("")}</tbody></table>`
  }

  rangeTipHtml(range) {
    return (
      '<div class="t-date">Custom range</div>' +
      `<div class="t-val">${escapeHtml(range.label)}</div>` +
      `<div class="t-lbl">${range.whole ? "Already showing all of it" : "Let go to apply, Esc to cancel"}</div>`
    )
  }

  reading(value) {
    return value == null ? this.missing : format(value, this.type)
  }

  tipHtml(time, value, shadow, open = false) {
    let compare = ""

    if (shadow != null && value != null) {
      let change = ""

      if (shadow > 0) {
        const delta = ((value - shadow) / shadow) * 100
        const good = this.type === "percent" && this.label.toLowerCase().includes("bounce") ? delta <= 0 : delta >= 0

        change = `<span class="${good ? "up" : "down"}">${delta >= 0 ? "\u2191" : "\u2193"}${Math.abs(delta).toFixed(0)}%</span>`
      } else if (value > 0) {
        change = '<span class="new">New</span>'
      }

      compare =
        '<div class="t-cmp"><span>Previous</span>' +
        `<b>${escapeHtml(format(shadow, this.type))}</b>${change}</div>`
    }

    return (
      `<div class="t-date">${escapeHtml(stamp(TIPS, this.interval, time))}</div>` +
      `<div class="t-val">${escapeHtml(this.reading(value))}</div>` +
      `<div class="t-lbl">${escapeHtml(this.label)}${open ? " so far" : ""}</div>${compare}`
    )
  }
}
