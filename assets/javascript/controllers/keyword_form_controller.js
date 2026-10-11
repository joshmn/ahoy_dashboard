import { Controller } from "../runtime/controllers.js"

// The keyword forms: what gets checked, and what it costs, kept in step with
// what is on the form.
//
// One controller for three screens — track one, import a list, track a batch —
// because they are the same decision at three sizes and the arithmetic behind
// the number in the corner is the same on all of them.
//
// A place row is read by the name of its fields rather than by its tag, because
// the same row is a country select beside a typed city when there is no place
// list to pick from, and two hidden fields behind a picker when there is.

const COUNTRY = '[name$="[place_countries][]"]'
const CITY = '[name$="[place_cities][]"]'

const sentence = (items) => {
  if (items.length < 3) return items.join(" and ")

  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`
}

const counted = (number, one, many) => `${number.toLocaleString("en-US")} ${number === 1 ? one : many}`

const leaf = (name) => name.split(",")[0].trim()

export default class extends Controller {
  static targets = ["query", "place", "add", "queryOut", "where", "device", "often", "monthly", "monthlyNoun", "perCheck", "checks", "over", "pick", "pasted", "total", "count", "limit", "submit"]
  static values = { costs: Object, durations: Object, month: Number, remaining: Number, limit: Number }

  connect() {
    const rows = this.placeTargets
    const used = rows.filter((row) => this.filled(row))

    rows.forEach((row, index) => {
      row.hidden = used.length ? !used.includes(row) : index > 0
    })

    this.layout()
    this.refresh()
  }

  // Adding a place starts one level up from the last one. Somebody who picked
  // Chicago almost always wants another city in Illinois next, and somebody who
  // picked Illinois wants another state. Starting from the top again every time
  // is four clicks back to where they already were.
  addPlace() {
    const next = this.placeTargets.find((row) => row.hidden)
    if (!next) return

    this.seed(next)
    next.hidden = false
    this.layout()
    this.refresh()

    this.opener(next)?.focus()
  }

  removePlace(event) {
    const row = event.currentTarget.closest("[data-dash--keyword-form-target~='place']")
    if (!row) return

    this.clear(row)
    row.hidden = true
    row.parentElement.appendChild(row)

    this.layout()
    this.refresh()

    if (this.hasAddTarget) this.addTarget.focus()
  }

  suggest(event) {
    if (!this.hasQueryTarget) return

    event.preventDefault()
    this.queryTarget.value = event.params.query || ""
    this.queryTarget.focus()
    this.refresh()
  }

  layout() {
    const rows = this.placeTargets
    const shown = rows.filter((row) => !row.hidden)

    shown.forEach((row, index) => {
      row.querySelectorAll("[data-place-label]").forEach((element) => {
        const text = element.dataset.placeLabel.replace("{n}", index + 1)

        if (element.tagName === "LABEL") element.textContent = text
        else element.setAttribute("aria-label", text)
      })

      const remove = row.querySelector("[data-remove]")
      if (!remove) return

      remove.hidden = shown.length < 2
      remove.setAttribute("aria-label", `Delete place ${index + 1}`)
    })

    if (this.hasAddTarget) this.addTarget.hidden = shown.length >= rows.length
  }

  refresh() {
    const places = this.placeTargets.filter((row) => !row.hidden && this.country(row)?.value)
    const pages = this.checked("pages")
    const frequency = this.checked("frequency")
    const depth = Number(pages?.value || 1)
    const duration = this.durationsValue[frequency?.value] || this.durationsValue.weekly
    const ratio = duration ? this.monthValue / duration : 0
    const perCheck = (Number(this.costsValue[depth]) || 0) * places.length
    const monthly = Math.ceil(perCheck * ratio)
    const checks = Math.ceil(places.length * depth * ratio)

    this.placeTargets.forEach((row) => this.paint(row))

    if (this.hasQueryOutTarget && this.hasQueryTarget) {
      const query = this.queryTarget.value.trim()

      this.queryOutTarget.textContent = query || "Not typed yet"
      this.queryOutTarget.classList.toggle("nil", !query)
    }

    if (this.hasWhereTarget) {
      const names = places.map((row) => this.placeName(row))

      this.whereTarget.textContent = sentence(names) || "No place picked"
      this.whereTarget.classList.toggle("nil", !names.length)
    }

    if (this.hasDeviceTarget) this.deviceTarget.textContent = this.labelFor(this.checked("device"))
    if (this.hasOftenTarget) this.oftenTarget.textContent = `${this.labelFor(frequency)}, ${this.labelFor(pages).toLowerCase()}`
    if (this.hasMonthlyTarget) this.monthlyTarget.textContent = monthly.toLocaleString("en-US")
    if (this.hasMonthlyNounTarget) this.monthlyNounTarget.textContent = `${monthly === 1 ? "search" : "searches"} a month`
    if (this.hasPerCheckTarget) this.perCheckTarget.textContent = counted(perCheck, "search", "searches")
    if (this.hasChecksTarget) this.checksTarget.textContent = counted(checks, "check", "checks")

    const count = this.hasSubmitTarget ? this.chosen : 1

    if (this.hasCountTarget) {
      this.countTarget.textContent = count === 0 ? "Nothing picked yet" : counted(count, "keyword", "keywords")
      this.countTarget.classList.toggle("nil", count === 0)
    }

    if (this.hasTotalTarget) {
      const free = !Number(this.costsValue[1])

      this.totalTarget.textContent = free ? counted(checks * count, "check", "checks") : counted(monthly * count, "unit", "units")
    }

    if (this.hasLimitTarget && this.hasLimitValue) this.limitTarget.hidden = count <= this.limitValue

    if (this.hasSubmitTarget) {
      this.submitTarget.value = count === 1 ? "Track 1 keyword" : `Track ${counted(count, "keyword", "keywords")}`
      this.submitTarget.disabled = count === 0
    }

    if (this.hasOverTarget && this.hasRemainingValue) this.overTarget.hidden = monthly * count <= this.remainingValue
  }

  // Ticked and pasted are one list, not two. The same keyword in both is one
  // keyword, which is what the server will make of it, so the number in the
  // corner should not say two.
  get chosen() {
    const seen = new Set()

    this.pickTargets.forEach((box) => {
      if (box.checked) seen.add(box.value.trim().toLowerCase())
    })

    if (this.hasPastedTarget) {
      this.pastedTarget.value.split("\n").forEach((line) => seen.add(line.trim().toLowerCase()))
    }

    seen.delete("")

    return seen.size
  }

  paint(row) {
    const text = row.querySelector("[data-place-text]")
    if (!text) return

    const name = row.dataset.placeName || ""
    const context = row.querySelector("[data-place-context]")

    text.textContent = name || "Pick a place"
    text.classList.toggle("nil", !name)

    if (!context) return

    context.textContent = row.dataset.placeParentLabel || ""
    context.hidden = Boolean(name) || !row.dataset.placeParentLabel
  }

  seed(row) {
    const shown = this.placeTargets.filter((other) => !other.hidden)
    const last = shown[shown.length - 1]
    if (!last) return

    const country = this.country(row)
    const city = this.city(row)

    if (!row.querySelector("[data-place-text]")) {
      if (country) country.value = this.country(last)?.value || ""
      if (city) city.value = ""
      return
    }

    row.dataset.placeParent = last.dataset.placeParent || ""
    row.dataset.placeParentLabel = last.dataset.placeParentLabel || ""
    row.dataset.placeName = ""
    row.dataset.placeCode = ""

    if (country) country.value = ""
    if (city) city.value = ""
  }

  clear(row) {
    const country = this.country(row)
    const city = this.city(row)

    if (country) country.value = ""
    if (city) city.value = ""

    row.dataset.placeName = ""
    row.dataset.placeCode = ""
    row.dataset.placeParent = ""
    row.dataset.placeParentLabel = ""
  }

  opener(row) {
    return row.querySelector("[data-tm-place]") || this.country(row)
  }

  country(row) {
    return row.querySelector(COUNTRY)
  }

  city(row) {
    return row.querySelector(CITY)
  }

  placeName(row) {
    if (row.dataset.placeName) return leaf(row.dataset.placeName)

    const city = this.city(row)?.value.trim()
    if (city) return leaf(city)

    const field = this.country(row)
    if (field?.tagName === "SELECT") return field.selectedOptions[0]?.text || ""

    return (field?.value || "").toUpperCase()
  }

  filled(row) {
    return Boolean(this.country(row)?.value || this.city(row)?.value.trim())
  }

  checked(name) {
    return this.element.querySelector(`input[type="radio"][name$="[${name}]"]:checked`)
  }

  labelFor(input) {
    if (!input) return ""

    return this.element.querySelector(`label[for="${input.id}"]`)?.textContent.trim() || ""
  }
}
