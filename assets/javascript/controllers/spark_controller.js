import { Controller } from "../runtime/controllers.js"
import { smoothPath } from "../runtime/path.js"

const TOP = 5
const FOOT = 3
const HEADROOM = 1.15

export default class extends Controller {
  static values = {
    values: Array,
    width: { type: Number, default: 200 },
    height: { type: Number, default: 44 }
  }

  connect() {
    const values = this.valuesValue
    if (!Array.isArray(values) || values.length < 2) return

    const width = this.widthValue
    const height = this.heightValue
    const top = Math.min(TOP, height / 4)
    const foot = Math.min(FOOT, height / 6)

    const peak = Math.max(...values) * HEADROOM
    const span = peak > 0 ? peak : 1
    const step = (width - 2) / (values.length - 1)

    const points = values.map((value, index) => [
      index * step + 1,
      height - foot - (value / span) * (height - top - foot)
    ])

    this.element.innerHTML = `<path class="pq-line" d="${smoothPath(points)}"/>`
  }
}
