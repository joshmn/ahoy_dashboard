import { Controller } from "../runtime/controllers.js"

// One box at the head of a list that ticks the rest of them. A Search Console
// import is nearly always taken whole, and forty clicks to say so is a form
// nobody finishes. The header box also reads back: part of a list ticked leaves
// it indeterminate rather than claiming everything or nothing.
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
