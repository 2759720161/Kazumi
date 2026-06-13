import { Logger } from '../../utils/Logger'

const logger = new Logger('HtmlParser')

export enum NodeType {
  ELEMENT = 1,
  TEXT = 3,
}

export class HtmlNode {
  nodeType: NodeType = NodeType.ELEMENT
  tagName: string = ''
  attributes: Map<string, string> = new Map()
  childNodes: HtmlNode[] = []
  textContent: string = ''
  parentNode: HtmlNode | null = null
}

export class HtmlDocument {
  root: HtmlNode | null = null

  getElementById(id: string): HtmlNode | null {
    return this._findById(this.root, id)
  }

  getElementsByTagName(tagName: string): HtmlNode[] {
    const results: HtmlNode[] = []
    this._collectByTagName(this.root, tagName.toLowerCase(), results)
    return results
  }

  getElementsByClassName(className: string): HtmlNode[] {
    const results: HtmlNode[] = []
    this._collectByClassName(this.root, className, results)
    return results
  }

  private _findById(node: HtmlNode | null, id: string): HtmlNode | null {
    if (!node) return null
    if (node.attributes.get('id') === id) return node
    for (let i = 0; i < node.childNodes.length; i++) {
      const found = this._findById(node.childNodes[i], id)
      if (found) return found
    }
    return null
  }

  private _collectByTagName(node: HtmlNode | null, tagName: string, results: HtmlNode[]): void {
    if (!node) return
    if (node.nodeType === NodeType.ELEMENT && node.tagName.toLowerCase() === tagName) {
      results.push(node)
    }
    for (let i = 0; i < node.childNodes.length; i++) {
      this._collectByTagName(node.childNodes[i], tagName, results)
    }
  }

  private _collectByClassName(node: HtmlNode | null, className: string, results: HtmlNode[]): void {
    if (!node) return
    if (node.nodeType === NodeType.ELEMENT) {
      const cls = node.attributes.get('class') ?? ''
      if (cls.split(/\s+/).includes(className)) {
        results.push(node)
      }
    }
    for (let i = 0; i < node.childNodes.length; i++) {
      this._collectByClassName(node.childNodes[i], className, results)
    }
  }
}

const VOID_ELEMENTS: string[] = [
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
  'link', 'meta', 'param', 'source', 'track', 'wbr'
]

const RAW_TEXT_ELEMENTS: string[] = ['script', 'style']

function isVoidElement(tag: string): boolean {
  for (let i = 0; i < VOID_ELEMENTS.length; i++) {
    if (VOID_ELEMENTS[i] === tag) return true
  }
  return false
}

function isRawTextElement(tag: string): boolean {
  for (let i = 0; i < RAW_TEXT_ELEMENTS.length; i++) {
    if (RAW_TEXT_ELEMENTS[i] === tag) return true
  }
  return false
}

export class HtmlParser {
  parse(html: string): HtmlDocument {
    const doc = new HtmlDocument()
    const root = new HtmlNode()
    root.nodeType = NodeType.ELEMENT
    root.tagName = 'root'
    root.parentNode = null

    const stack: HtmlNode[] = [root]
    let pos = 0
    const len = html.length

    while (pos < len) {
      const top = stack[stack.length - 1]

      if (html[pos] === '<') {
        if (pos + 3 < len && html[pos + 1] === '!' && html[pos + 2] === '-' && html[pos + 3] === '-') {
          const end = html.indexOf('-->', pos + 4)
          pos = end === -1 ? len : end + 3
          continue
        }

        if (pos + 1 < len && html[pos + 1] === '!') {
          const end = html.indexOf('>', pos + 2)
          pos = end === -1 ? len : end + 1
          continue
        }

        if (pos + 1 < len && html[pos + 1] === '/') {
          let closePos = pos + 2
          while (closePos < len && html[closePos] !== '>') closePos++
          if (closePos < len) {
            const closeTag = html.substring(pos + 2, closePos).trim().toLowerCase()
            let found = false
            for (let si = stack.length - 1; si >= 1; si--) {
              if (stack[si].tagName === closeTag) {
                for (let sj = stack.length - 1; sj >= si; sj--) {
                  stack.pop()
                }
                found = true
                break
              }
            }
            if (!found) {
              // orphan close tag, skip
            }
            pos = closePos + 1
          } else {
            pos = len
          }
          continue
        }

        const tagStart = pos + 1
        let tp = tagStart
        const TAG_NAME_RE: RegExp = /[a-zA-Z0-9\-]/
        let tagName = ''
        while (tp < len && TAG_NAME_RE.test(html[tp])) {
          tagName += html[tp]
          tp++
        }
        if (tagName.length === 0) {
          const textNode = new HtmlNode()
          textNode.nodeType = NodeType.TEXT
          textNode.textContent = '<'
          textNode.parentNode = top
          top.childNodes.push(textNode)
          pos++
          continue
        }

        const lowerTag = tagName.toLowerCase()
        const attrs = new Map<string, string>()
        tp = this._parseAttributes(html, tp, attrs)
        const selfClosing = attrs.has('__selfClosing')
        attrs.delete('__selfClosing')

        const gtPos = html.indexOf('>', tp)
        const endOfTag = gtPos === -1 ? len : gtPos + 1

        const node = new HtmlNode()
        node.nodeType = NodeType.ELEMENT
        node.tagName = lowerTag
        node.attributes = attrs
        node.parentNode = top
        top.childNodes.push(node)

        if (selfClosing || isVoidElement(lowerTag)) {
          pos = endOfTag
          continue
        }

        if (isRawTextElement(lowerTag)) {
          const rawClose = `</${lowerTag}>`
          let rawEnd = html.toLowerCase().indexOf(rawClose, endOfTag)
          if (rawEnd === -1) rawEnd = len
          const rawText = html.substring(endOfTag, rawEnd)
          if (rawText.length > 0) {
            const textNode = new HtmlNode()
            textNode.nodeType = NodeType.TEXT
            textNode.textContent = rawText
            textNode.parentNode = node
            node.childNodes.push(textNode)
          }
          pos = rawEnd === len ? len : rawEnd + rawClose.length
          continue
        }

        stack.push(node)
        pos = endOfTag
      } else {
        let textEnd = html.indexOf('<', pos)
        if (textEnd === -1) textEnd = len
        const text = html.substring(pos, textEnd)
        if (text.length > 0) {
          const textNode = new HtmlNode()
          textNode.nodeType = NodeType.TEXT
          textNode.textContent = text
          textNode.parentNode = top
          top.childNodes.push(textNode)
        }
        pos = textEnd
      }
    }

    doc.root = root
    return doc
  }

  private _parseAttributes(html: string, pos: number, attrs: Map<string, string>): number {
    const len = html.length
    while (pos < len) {
      while (pos < len && (html[pos] === ' ' || html[pos] === '\t' || html[pos] === '\n' || html[pos] === '\r')) pos++
      if (pos >= len || html[pos] === '>' || html[pos] === '/') break

      if (html[pos] === '/') {
        attrs.set('__selfClosing', '')
        pos++
        continue
      }

      let attrName = ''
      while (pos < len && html[pos] !== '=' && html[pos] !== ' ' && html[pos] !== '>' && html[pos] !== '/') {
        attrName += html[pos++]
      }

      while (pos < len && (html[pos] === ' ' || html[pos] === '\t')) pos++

      if (pos < len && html[pos] === '=') {
        pos++
        while (pos < len && (html[pos] === ' ' || html[pos] === '\t')) pos++
        if (pos < len && (html[pos] === '"' || html[pos] === "'")) {
          const quote = html[pos++]
          let attrValue = ''
          while (pos < len && html[pos] !== quote) attrValue += html[pos++]
          if (pos < len) pos++
          attrs.set(attrName.toLowerCase(), attrValue)
        } else {
          let attrValue = ''
          while (pos < len && html[pos] !== ' ' && html[pos] !== '>' && html[pos] !== '/') {
            attrValue += html[pos++]
          }
          attrs.set(attrName.toLowerCase(), attrValue)
        }
      } else {
        attrs.set(attrName.toLowerCase(), '')
      }
    }
    return pos
  }
}
