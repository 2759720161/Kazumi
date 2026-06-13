import { HtmlDocument, HtmlNode, NodeType } from './HtmlParser'

export class XPathResult {
  nodes: HtmlNode[] = []
  strings: string[] = []

  get stringValue(): string {
    return this.strings.length > 0 ? this.strings[0] : ''
  }

  get numberValue(): number {
    return parseFloat(this.stringValue)
  }

  get booleanValue(): boolean {
    return this.nodes.length > 0 || this.strings.length > 0
  }
}

export class XPathEvaluator {
  evaluate(xpath: string, context: HtmlDocument | HtmlNode): XPathResult {
    const root = context instanceof HtmlDocument ? context.root : context
    if (!root) return new XPathResult()

    const tokens = this._tokenize(xpath)
    return this._evaluateTokens(tokens, root)
  }

  select(xpath: string, context: HtmlDocument | HtmlNode): HtmlNode[] {
    return this.evaluate(xpath, context).nodes
  }

  selectString(xpath: string, context: HtmlDocument | HtmlNode): string {
    return this.evaluate(xpath, context).stringValue
  }

  selectStrings(xpath: string, context: HtmlDocument | HtmlNode): string[] {
    return this.evaluate(xpath, context).strings
  }

  private _tokenize(xpath: string): string[] {
    const tokens: string[] = []
    let i = 0
    const len = xpath.length
    while (i < len) {
      while (i < len && xpath[i] === ' ') i++
      if (i >= len) break

      if (xpath[i] === '/') {
        if (i + 1 < len && xpath[i + 1] === '/') {
          tokens.push('//')
          i += 2
        } else {
          tokens.push('/')
          i++
        }
      } else if (xpath[i] === '[') {
        let bracket = 1
        let j = i + 1
        while (j < len && bracket > 0) {
          if (xpath[j] === '[') bracket++
          else if (xpath[j] === ']') bracket--
          j++
        }
        tokens.push(xpath.substring(i, j))
        i = j
      } else if (xpath[i] === '@') {
        let j = i + 1
        const ATTR_NAME_RE: RegExp = /[a-zA-Z0-9_\-]/
        while (j < len && ATTR_NAME_RE.test(xpath[j])) j++
        tokens.push(xpath.substring(i, j))
        i = j
      } else if (xpath[i] === '"' || xpath[i] === "'") {
        const quote = xpath[i]
        let j = i + 1
        while (j < len && xpath[j] !== quote) j++
        tokens.push(xpath.substring(i, j + 1))
        i = j + 1
      } else if (xpath[i] === '(' || xpath[i] === ')') {
        tokens.push(xpath[i])
        i++
      } else {
        let j = i
        const STEP_RE: RegExp = /[\[\]\/\(@\s]/
        while (j < len && !STEP_RE.test(xpath[j])) j++
        if (j > i) {
          let token = xpath.substring(i, j)
          if (j < len && xpath[j] === '(') {
            let parenStart = j
            j++
            let parenCount = 1
            while (j < len && parenCount > 0) {
              if (xpath[j] === '(') parenCount++
              else if (xpath[j] === ')') parenCount--
              j++
            }
            token = xpath.substring(i, j)
          }
          tokens.push(token)
          i = j
        } else {
          tokens.push(xpath[i])
          i++
        }
      }
    }
    return tokens
  }

  private _evaluateTokens(tokens: string[], root: HtmlNode): XPathResult {
    const result = new XPathResult()
    let currentNodes: HtmlNode[] = [root]
    let i = 0

    while (i < tokens.length) {
      const token = tokens[i]

      if (token === '//' || token === '/') {
        i++
        if (i >= tokens.length) break

        const axis = token
        const nextToken = tokens[i]

        if (nextToken === 'text()' ) {
          const textNodes: HtmlNode[] = []
          for (const node of currentNodes) {
            this._collectTextNodes(node, axis === '//', textNodes)
          }
          result.nodes = textNodes
          result.strings = textNodes.map(n => n.textContent.trim()).filter(s => s.length > 0)
          i++
          continue
        }

        if (nextToken.startsWith('@')) {
          const attrName = nextToken.substring(1)
          result.strings = currentNodes
            .filter(n => n.attributes.has(attrName))
            .map(n => n.attributes.get(attrName) ?? '')
          result.nodes = currentNodes
          i++
          continue
        }

        let tagName = nextToken
        let predicate: string | null = null

        if (i + 1 < tokens.length && tokens[i + 1].startsWith('[')) {
          predicate = tokens[i + 1]
          i++
        }

        const nextNodes: HtmlNode[] = []
        for (const node of currentNodes) {
          let found = this._findChildren(node, tagName, axis === '//')
          if (predicate) {
            found = this._applyPredicate(found, predicate)
          }
          nextNodes.push(...found)
        }

        currentNodes = nextNodes

        i++
      } else if (token.startsWith('@')) {
        const attrName = token.substring(1)
        result.strings = currentNodes
          .filter(n => n.attributes.has(attrName))
          .map(n => n.attributes.get(attrName) ?? '')
        result.nodes = currentNodes
        i++
      } else if (token === 'text()') {
        result.strings = currentNodes
          .flatMap(n => n.childNodes.filter(c => c.nodeType === NodeType.TEXT))
          .map(n => n.textContent.trim())
          .filter(s => s.length > 0)
        i++
      } else {
        i++
      }
    }

    if (result.nodes.length === 0 && result.strings.length === 0) {
      result.nodes = currentNodes
    }

    return result
  }

  private _findChildren(node: HtmlNode, tagName: string, recursive: boolean): HtmlNode[] {
    const results: HtmlNode[] = []
    const targetTag = tagName.toLowerCase()

    if (tagName === '*') {
      this._collectAllElements(node, recursive, results)
    } else {
      this._collectByTag(node, targetTag, recursive, results)
    }

    return results
  }

  private _collectByTag(node: HtmlNode, tagName: string, recursive: boolean, results: HtmlNode[]): void {
    for (const child of node.childNodes) {
      if (child.nodeType === NodeType.ELEMENT && child.tagName === tagName) {
        results.push(child)
      }
      if (recursive && child.nodeType === NodeType.ELEMENT) {
        this._collectByTag(child, tagName, recursive, results)
      }
    }
  }

  private _collectAllElements(node: HtmlNode, recursive: boolean, results: HtmlNode[]): void {
    for (const child of node.childNodes) {
      if (child.nodeType === NodeType.ELEMENT) {
        results.push(child)
        if (recursive) {
          this._collectAllElements(child, recursive, results)
        }
      }
    }
  }

  private _collectTextNodes(node: HtmlNode, recursive: boolean, results: HtmlNode[]): void {
    for (const child of node.childNodes) {
      if (child.nodeType === NodeType.TEXT && child.textContent.trim().length > 0) {
        results.push(child)
      }
      if (recursive) {
        this._collectTextNodes(child, recursive, results)
      }
    }
  }

  private _applyPredicate(nodes: HtmlNode[], predicate: string): HtmlNode[] {
    const inner = predicate.substring(1, predicate.length - 1)

    const posMatch = inner.match(/^(\d+)$/)
    if (posMatch) {
      const pos = parseInt(posMatch[1]) - 1
      return pos >= 0 && pos < nodes.length ? [nodes[pos]] : []
    }

    const lastMatch = inner.match(/^last\(\)$/)
    if (lastMatch) {
      return nodes.length > 0 ? [nodes[nodes.length - 1]] : []
    }

    const attrMatch = inner.match(/^@([a-zA-Z0-9_\-]+)\s*=\s*['"]([^'"]*)['"]$/)
    if (attrMatch) {
      const attrName = attrMatch[1].toLowerCase()
      const attrValue = attrMatch[2]
      return nodes.filter(n => n.attributes.get(attrName) === attrValue)
    }

    const attrContainsMatch = inner.match(/^contains\(@([a-zA-Z0-9_\-]+),\s*['"]([^'"]*)['"]\)$/)
    if (attrContainsMatch) {
      const attrName = attrContainsMatch[1].toLowerCase()
      const substring = attrContainsMatch[2]
      return nodes.filter(n => (n.attributes.get(attrName) ?? '').includes(substring))
    }

    const classMatch = inner.match(/^contains\(concat\(['"]\s['"],\s*@class,\s*['"]\s['"]\),\s*['"]([^'"]+)['"]\)$/)
    if (classMatch) {
      const className = classMatch[1]
      return nodes.filter(n => {
        const cls = n.attributes.get('class') ?? ''
        return cls.split(/\s+/).includes(className)
      })
    }

    const textMatch = inner.match(/^contains\(text\(\),\s*['"]([^'"]*)['"]\)$/)
    if (textMatch) {
      const substring = textMatch[1]
      return nodes.filter(n => this._getTextContent(n).includes(substring))
    }

    const andMatch = inner.match(/^(.+?)\s+and\s+(.+)$/)
    if (andMatch) {
      const left = this._applyPredicate(nodes, `[${andMatch[1]}]`)
      const right = this._applyPredicate(nodes, `[${andMatch[2]}]`)
      const rightSet = new Set<HtmlNode>()
      for (const n of right) rightSet.add(n)
      return left.filter(n => rightSet.has(n))
    }

    const orMatch = inner.match(/^(.+?)\s+or\s+(.+)$/)
    if (orMatch) {
      const left = this._applyPredicate(nodes, `[${orMatch[1]}]`)
      const right = this._applyPredicate(nodes, `[${orMatch[2]}]`)
      const leftSet = new Set<HtmlNode>()
      for (const n of left) leftSet.add(n)
      return [...left, ...right.filter(n => !leftSet.has(n))]
    }

    return nodes
  }

  private _getTextContent(node: HtmlNode): string {
    if (node.nodeType === NodeType.TEXT) return node.textContent
    let text = ''
    for (const child of node.childNodes) {
      text += this._getTextContent(child)
    }
    return text
  }
}
