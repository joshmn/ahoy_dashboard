export async function getJSON(url, { signal } = {}) {
  const response = await fetch(url, { headers: { Accept: "application/json" }, signal })
  if (!response.ok) throw new Error(String(response.status))

  return response.json()
}

export async function getFragment(url, { frame, signal } = {}) {
  const response = await fetch(url, {
    signal,
    credentials: "same-origin",
    headers: { Accept: "text/html", "Tm-Frame": frame }
  })
  if (!response.ok || response.redirected) throw new Error(`${frame} could not be loaded`)

  return response.text()
}
