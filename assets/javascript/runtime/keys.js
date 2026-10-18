export const wrap = (at, step, length) => {
  if (at < 0) return step < 0 ? length - 1 : 0

  return (at + step + length) % length
}

export const modified = (event) => event.metaKey || event.ctrlKey || event.shiftKey || event.altKey
