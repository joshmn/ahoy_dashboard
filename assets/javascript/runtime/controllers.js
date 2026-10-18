const REGISTRY = new Map()
const BOUND = new WeakMap()
const LISTENING = new Set()

const DEFAULT_EVENTS = {
  a: "click",
  button: "click",
  form: "submit",
  input: "input",
  select: "change",
  textarea: "input",
  details: "toggle"
}

const DESCRIPTOR = /^(?:(.+?)->)?(.+?)#([^:]+)$/

const dasherize = (name) => name.replace(/([A-Z])/g, "-$1").toLowerCase()

const camelize = (name) => name.replace(/[-_](.)/g, (_match, letter) => letter.toUpperCase())

const readValue = (raw, type, fallback) => {
  if (raw === null) return fallback

  if (type === Number) {
    const number = Number(raw)
    return Number.isFinite(number) ? number : fallback
  }

  if (type === Boolean) return raw !== "false"

  if (type === Object || type === Array) {
    try {
      return JSON.parse(raw)
    } catch {
      return fallback
    }
  }

  return raw
}

const EMPTY = { String: "", Number: 0, Boolean: false, Object: {}, Array: [] }

const declaration = (spec) => {
  if (spec && spec.type) return { type: spec.type, fallback: "default" in spec ? spec.default : EMPTY[spec.type.name] }

  return { type: spec, fallback: EMPTY[spec.name] }
}

const defineTargets = (klass, identifier) => {
  const names = klass.targets || []

  names.forEach((name) => {
    const selector = `[data-${identifier}-target~="${name}"]`

    Object.defineProperties(klass.prototype, {
      [`${name}Target`]: {
        configurable: true,
        get() {
          return this.element.matches(selector) ? this.element : this.element.querySelector(selector)
        }
      },
      [`${name}Targets`]: {
        configurable: true,
        get() {
          const found = Array.from(this.element.querySelectorAll(selector))
          return this.element.matches(selector) ? [ this.element, ...found ] : found
        }
      },
      [`has${name[0].toUpperCase()}${name.slice(1)}Target`]: {
        configurable: true,
        get() {
          return this.element.matches(selector) || this.element.querySelector(selector) !== null
        }
      }
    })
  })
}

const defineValues = (klass, identifier) => {
  const specs = klass.values || {}

  Object.entries(specs).forEach(([name, spec]) => {
    const { type, fallback } = declaration(spec)
    const attribute = `data-${identifier}-${dasherize(name)}-value`

    Object.defineProperties(klass.prototype, {
      [`${name}Value`]: {
        configurable: true,
        get() {
          return readValue(this.element.getAttribute(attribute), type, fallback)
        },
        set(value) {
          const raw = type === Object || type === Array ? JSON.stringify(value) : String(value)
          this.element.setAttribute(attribute, raw)
        }
      },
      [`has${name[0].toUpperCase()}${name.slice(1)}Value`]: {
        configurable: true,
        get() {
          return this.element.hasAttribute(attribute)
        }
      }
    })
  })
}

export class Controller {
  constructor(element, identifier) {
    this.element = element
    this.identifier = identifier
  }

  connect() {}

  disconnect() {}
}

export const register = (identifier, klass) => {
  defineTargets(klass, identifier)
  defineValues(klass, identifier)
  REGISTRY.set(identifier, klass)
}

export const controllerFor = (element, identifier) => BOUND.get(element)?.get(identifier) || null

const identifiersOn = (element) => (element.getAttribute("data-controller") || "").trim().split(/\s+/).filter(Boolean)

const connectElement = (element) => {
  const wanted = identifiersOn(element)
  if (!wanted.length) return

  let instances = BOUND.get(element)

  if (!instances) {
    instances = new Map()
    BOUND.set(element, instances)
  }

  wanted.forEach((identifier) => {
    if (instances.has(identifier)) return

    const klass = REGISTRY.get(identifier)
    if (!klass) return

    const instance = new klass(element, identifier)
    instances.set(identifier, instance)
    instance.connect()
  })
}

const disconnectElement = (element, only = null) => {
  const instances = BOUND.get(element)
  if (!instances) return

  instances.forEach((instance, identifier) => {
    if (only && !only.includes(identifier)) return

    instance.disconnect()
    instances.delete(identifier)
  })

  if (!instances.size) BOUND.delete(element)
}

const eachIn = (root, selector, work) => {
  if (root.nodeType !== Node.ELEMENT_NODE) return

  if (root.matches(selector)) work(root)
  root.querySelectorAll(selector).forEach(work)
}

const listenFor = (root) => {
  eachIn(root, "[data-action]", (element) => {
    ;(element.getAttribute("data-action") || "").trim().split(/\s+/).forEach((descriptor) => {
      const parsed = DESCRIPTOR.exec(descriptor)
      if (!parsed) return

      const type = parsed[1] || DEFAULT_EVENTS[element.tagName.toLowerCase()] || "click"
      if (LISTENING.has(type)) return

      LISTENING.add(type)
      document.addEventListener(type, dispatch)
    })
  })
}

const connectTree = (root) => {
  listenFor(root)
  eachIn(root, "[data-controller]", connectElement)
}

const disconnectTree = (root) => {
  eachIn(root, "[data-controller]", (element) => disconnectElement(element))
}

const paramsFor = (element, identifier) => {
  const prefix = `data-${identifier}-`
  const params = {}

  Array.from(element.attributes).forEach(({ name, value }) => {
    if (!name.startsWith(prefix) || !name.endsWith("-param")) return

    params[camelize(name.slice(prefix.length, -"-param".length))] = value
  })

  return params
}

const call = (element, descriptor, event) => {
  const parsed = DESCRIPTOR.exec(descriptor)
  if (!parsed) return

  const [, named, identifier, method] = parsed
  const type = named || DEFAULT_EVENTS[element.tagName.toLowerCase()] || "click"
  if (type !== event.type) return

  const scope = element.closest(`[data-controller~="${identifier}"]`)
  if (!scope) return

  const instance = controllerFor(scope, identifier)
  if (!instance || typeof instance[method] !== "function") return

  const owner = Object.getOwnPropertyDescriptor(event, "currentTarget")
  Object.defineProperty(event, "currentTarget", { value: element, configurable: true })
  event.params = paramsFor(element, identifier)

  try {
    instance[method](event)
  } finally {
    if (owner) {
      Object.defineProperty(event, "currentTarget", owner)
    } else {
      delete event.currentTarget
    }
  }
}

const dispatch = (event) => {
  let node = event.target instanceof Element ? event.target : null

  while (node) {
    const spec = node.getAttribute("data-action")

    if (spec) spec.trim().split(/\s+/).forEach((descriptor) => call(node, descriptor, event))

    node = node.parentElement
  }
}

export const start = () => {
  connectTree(document.documentElement)

  new MutationObserver((records) => {
    records.forEach((record) => {
      if (record.type === "attributes") {
        const element = record.target
        const wanted = identifiersOn(element)
        const bound = Array.from(BOUND.get(element)?.keys() || [])

        disconnectElement(element, bound.filter((identifier) => !wanted.includes(identifier)))
        connectElement(element)
        return
      }

      record.removedNodes.forEach((node) => disconnectTree(node))
      record.addedNodes.forEach((node) => connectTree(node))
    })
  }).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-controller"]
  })
}
