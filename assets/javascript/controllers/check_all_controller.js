import { Controller } from "../runtime/controllers.js"

export default class extends Controller {
  static targets = ["master", "box"]

  connect() {
    this.sync()
  }

  toggle() {
    const on = this.masterTarget.checked

    this.boxTargets.forEach((box) => {
      box.checked = on
    })
  }

  sync() {
    if (!this.hasMasterTarget) return

    const boxes = this.boxTargets
    const ticked = boxes.filter((box) => box.checked).length

    this.masterTarget.checked = boxes.length > 0 && ticked === boxes.length
    this.masterTarget.indeterminate = ticked > 0 && ticked < boxes.length
  }
}
