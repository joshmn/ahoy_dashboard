export const plural = (count, one, many = `${one}s`) => (count === 1 ? one : many)

export const counted = (count, one, many) => `${count.toLocaleString("en-US")} ${plural(count, one, many)}`

export const sentence = (items) => {
  if (items.length < 3) return items.join(" and ")

  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`
}
