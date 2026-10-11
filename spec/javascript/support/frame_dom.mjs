class FrameNode {
  constructor(tag = "tm-frame") {
    this.tagName = tag.toUpperCase()
    this.attributes = new Map()
    this.children = []
    this.listeners = new Map()
    this.dataset = {}
    this.isConnected = true
  }

  get childNodes() { return this.children }
  get textContent() { return this.children.map((child) => typeof child === "string" ? child : child.textContent).join("") }
  set textContent(value) { this.replaceChildren(value) }
  setAttribute(key, value) { this.attributes.set(key, String(value)) }
  getAttribute(key) { return this.attributes.get(key) ?? null }
  hasAttribute(key) { return this.attributes.has(key) }
  removeAttribute(key) { this.attributes.delete(key) }
  addEventListener(name, callback) { this.listeners.set(name, callback) }
  click() { return this.listeners.get("click")?.({ currentTarget: this }) }

  append(...children) {
    children.forEach((child) => {
      if (typeof child !== "string") child.parentNode = this
      this.children.push(child)
    })
  }

  replaceChildren(...children) {
    this.children.forEach((child) => { if (typeof child !== "string") child.parentNode = null })
    this.children = []
    this.append(...children)
  }

  remove() {
    if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((child) => child !== this)
    this.parentNode = null
  }

  querySelector(selector) {
    if (selector !== ":scope > .tm-frame-error") throw new Error(`Unexpected selector: ${selector}`)

    return this.children.find((child) => child.className?.split(" ").includes("tm-frame-error")) || null
  }
}

export const installFrameDom = () => {
  globalThis.HTMLElement = FrameNode
  globalThis.CSS = { escape: (id) => id }
  globalThis.document = { createElement: (tag) => new FrameNode(tag) }
  globalThis.DOMParser = class {
    parseFromString(html) {
      return {
        querySelector(selector) {
          const match = html.match(/^<tm-frame id="([^"]+)">([\s\S]*)<\/tm-frame>$/)
          if (!match || selector !== `tm-frame#${match[1]}`) return null

          const result = new FrameNode()
          result.textContent = match[2]
          return result
        },
      }
    }
  }
}
