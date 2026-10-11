const question = (element) => element?.closest("[data-tm-confirm]")?.getAttribute("data-tm-confirm")

const onClick = (event) => {
  if (event.defaultPrevented) return

  const asked = question(event.target instanceof Element ? event.target : null)
  if (!asked || window.confirm(asked)) return

  event.preventDefault()
  event.stopImmediatePropagation()
}

const onSubmit = (event) => {
  if (event.defaultPrevented) return

  const form = event.target
  if (!(form instanceof HTMLFormElement)) return

  const asked = form.getAttribute("data-tm-confirm")
  if (!asked || window.confirm(asked)) return

  event.preventDefault()
  event.stopImmediatePropagation()
}

export const start = () => {
  document.addEventListener("click", onClick)
  document.addEventListener("submit", onSubmit)
}
