const UNITS = [[1e9, "B"], [1e6, "M"], [1e3, "k"]]
const COMPACT_DECIMALS_BELOW = 100

const tenths = (value) => {
  const [whole, fraction = ""] = String(value).split(".")
  const rest = fraction.slice(1).replace(/0+$/, "")
  let units = Number(whole) * 10 + Number(fraction[0] || 0)
  if (rest > "5" || (rest === "5" && units % 2 === 1)) units += 1

  return `${Math.floor(units / 10)}.${units % 10}`
}

export function delimited(n) {
  return Math.round(n).toLocaleString("en-US")
}

function abbreviate(n, printTenths) {
  let index = UNITS.findIndex(([size]) => Math.round(Math.abs(n)) >= size)
  if (index === -1) return delimited(n)

  let scaled = n / UNITS[index][0]
  if (Math.round(Math.abs(scaled)) >= 1000 && index > 0) {
    index -= 1
    scaled = n / UNITS[index][0]
  }

  const text = Math.abs(Math.round(scaled * 10) / 10) < COMPACT_DECIMALS_BELOW ? printTenths(scaled) : String(Math.round(scaled))

  return text + UNITS[index][1]
}

export function compact(n) {
  const text = abbreviate(Math.abs(n), tenths)

  return n < 0 && text !== "0" ? `-${text}` : text
}

export function duration(n) {
  const total = Math.round(n)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60

  if (hours > 0) return `${hours}h ${minutes}m`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

export function format(value, type) {
  const n = Number(value) || 0

  switch (type) {
    case "decimal":
      return n.toFixed(2)
    case "percent":
      return `${Math.round(n)}%`
    case "rate":
      return `${Math.round(n * 10) / 10}%`
    case "duration":
      return duration(n)
    case "currency":
      return `$${delimited(n)}`
    default:
      return delimited(n)
  }
}

export function tick(value, type) {
  const n = Number(value) || 0

  if (type === "duration") return n >= 60 ? `${Math.round(n / 60)}m` : `${Math.round(n)}s`
  if (type === "decimal") return n.toFixed(1)
  if (!type || type === "integer") return abbreviate(n, (scaled) => scaled.toFixed(1))

  return format(n, type)
}
