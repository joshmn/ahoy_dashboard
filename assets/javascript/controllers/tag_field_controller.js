import { Controller } from "../runtime/controllers.js"

const split = (value) => value.split(",").map((part) => part.trim().replace(/\s+/g, " ")).filter(Boolean)

export default class extends Controller {
  static targets = ["entry", "list", "template"]
  static values = { name: String }

  connect() {
    const initial = split(this.entryTarget.value)

    this.entryTarget.value = ""
    this.entryTarget.name = this.nameValue
    initial.forEach((tag) => this.add(tag))
  }

  key(event) {
    if (event.key === "Enter" || event.key === ",") {
      if (event.key === "Enter" && this.entryTarget.value.trim() === "") return

      event.preventDefault()
      this.commit()
      return
    }

    if (event.key === "Backspace" && this.entryTarget.value === "") {
      const last = this.chips().pop()
      if (!last) return

      event.preventDefault()
      this.entryTarget.value = last.querySelector("input").value
      last.remove()
      this.layout()
    }
  }

  commit() {
    split(this.entryTarget.value).forEach((tag) => this.add(tag))
    this.entryTarget.value = ""
  }

  remove(event) {
    event.currentTarget.closest("li")?.remove()
    this.layout()
    this.entryTarget.focus()
  }

  add(tag) {
    if (this.chips().some((chip) => chip.querySelector("input").value.toLowerCase() === tag.toLowerCase())) return

    const chip = this.templateTarget.content.firstElementChild.cloneNode(true)
    chip.querySelector("[data-tag-text]").textContent = tag
    chip.querySelector("button").setAttribute("aria-label", `Remove tag ${tag}`)

    const input = chip.querySelector("input")
    input.name = this.nameValue
    input.value = tag

    this.listTarget.appendChild(chip)
    this.layout()
  }

  chips() {
    return Array.from(this.listTarget.children)
  }

  layout() {
    this.listTarget.hidden = this.chips().length === 0
  }
}
