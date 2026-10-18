export const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((done, failed) => { resolve = done; reject = failed })
  return { promise, resolve, reject }
}
