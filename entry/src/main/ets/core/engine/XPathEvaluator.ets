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

enum StepType {
  SELF,
  DESCENDANT
}

enum AxisType {
  CHILD,
  DESCENDANT,
  DESCENDANT_OR_SELF,
  PARENT,
  SELF,
  ANCESTOR,
  ANCESTOR_OR_SELF,
  FOLLOWING_SIBLING,
  PRECEDING_SIBLING,
  FOLLOWING,
  PRECEDING,
  ATTRIBUTE
}

class XPathStep {
  stepType: StepType = StepType.SELF
  axis: AxisType = AxisType.CHILD
  nodeTest: string = ''
  predicates: string[] = []
  attr: string = ''
  func: string = ''
}

class XPathPath {
  steps: XPathStep[] = []
}

class AttrOpVal {
  attr: string = ''
  op: string = ''
  val: string = ''
}

class TextOpVal {
  op: string = ''
  val: string = ''
}

class LogicalSplit {
  left: string = ''
  right: string = ''
}

export class XPathEvaluator {
  evaluate(xpath: string, context: HtmlDocument | HtmlNode): XPathResult {
    const root = context instanceof HtmlDocument ? context.root : context
    if (!root) return new XPathResult()

    const trimmed = xpath.trim()
    if (trimmed.length === 0) return new XPathResult()

    const paths = this._splitUnion(trimmed)
    const combined = new XPathResult()
    const seenNodes = new Set<HtmlNode>()

    for (let p = 0; p < paths.length; p++) {
      const pathResult = this._evaluatePath(paths[p], root)
      for (let i = 0; i < pathResult.nodes.length; i++) {
        if (!seenNodes.has(pathResult.nodes[i])) {
          seenNodes.add(pathResult.nodes[i])
          combined.nodes.push(pathResult.nodes[i])
        }
      }
      for (let i = 0; i < pathResult.strings.length; i++) {
        combined.strings.push(pathResult.strings[i])
      }
    }

    return combined
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

  private _splitUnion(xpath: string): string[] {
    const parts: string[] = []
    let current = ''
    let depth = 0
    let i = 0
    while (i < xpath.length) {
      if (xpath[i] === '[') depth++
      else if (xpath[i] === ']') depth--
      else if (xpath[i] === '|' && depth === 0) {
        const trimmed = current.trim()
        if (trimmed.length > 0) parts.push(trimmed)
        current = ''
        i++
        continue
      }
      current += xpath[i]
      i++
    }
    const trimmed = current.trim()
    if (trimmed.length > 0) parts.push(trimmed)
    return parts
  }

  private _evaluatePath(xpath: string, root: HtmlNode): XPathResult {
    const path = this._parsePath(xpath)
    if (path.steps.length === 0) return new XPathResult()

    let currentNodes: HtmlNode[] = [root]

    for (let si = 0; si < path.steps.length; si++) {
      const step = path.steps[si]
      const isLast = si === path.steps.length - 1

      const nextNodes: HtmlNode[] = []
      const nextSeen = new Set<HtmlNode>()

      for (let ci = 0; ci < currentNodes.length; ci++) {
        const contextNode = currentNodes[ci]

        const expanded: HtmlNode[] = step.stepType === StepType.DESCENDANT
          ? this._descendantOrSelf(contextNode)
          : [contextNode]

        for (let ei = 0; ei < expanded.length; ei++) {
          const expandedNode = expanded[ei]
          const axisNodes = this._applyAxis(step.axis, expandedNode)
          const filtered = this._filterByNodeTest(axisNodes, step.nodeTest, step.axis, expandedNode)

          for (let pi = 0; pi < step.predicates.length; pi++) {
            const predResult = this._applyPredicate(filtered, step.predicates[pi], expandedNode)
            filtered.length = 0
            for (let fi = 0; fi < predResult.length; fi++) {
              filtered.push(predResult[fi])
            }
          }

          for (let fi = 0; fi < filtered.length; fi++) {
            if (!nextSeen.has(filtered[fi])) {
              nextSeen.add(filtered[fi])
              nextNodes.push(filtered[fi])
            }
          }
        }
      }

      currentNodes = nextNodes

      if (isLast && (step.attr.length > 0 || step.func.length > 0 || step.axis === AxisType.ATTRIBUTE)) {
        const result = new XPathResult()
        result.nodes = currentNodes

        if (step.axis === AxisType.ATTRIBUTE) {
          for (let ni = 0; ni < currentNodes.length; ni++) {
            const node = currentNodes[ni]
            if (step.nodeTest === '*') {
              const keys = Array.from(node.attributes.keys())
              for (let ki = 0; ki < keys.length; ki++) {
                const val = node.attributes.get(keys[ki]) ?? ''
                if (val.length > 0) {
                  result.strings.push(val)
                }
              }
            } else {
              const val = node.attributes.get(step.nodeTest.toLowerCase()) ?? ''
              if (val.length > 0) {
                result.strings.push(val)
              }
            }
          }
        } else if (step.attr.length > 0) {
          for (let ni = 0; ni < currentNodes.length; ni++) {
            const node = currentNodes[ni]
            if (step.attr === '*') {
              const keys = Array.from(node.attributes.keys())
              for (let ki = 0; ki < keys.length; ki++) {
                const val = node.attributes.get(keys[ki]) ?? ''
                if (val.length > 0) {
                  result.strings.push(val)
                }
              }
            } else {
              const val = node.attributes.get(step.attr.toLowerCase()) ?? ''
              if (val.length > 0) {
                result.strings.push(val)
              }
            }
          }
        } else if (step.func === 'text()' || step.func === 'string()') {
          for (let ni = 0; ni < currentNodes.length; ni++) {
            const text = currentNodes[ni].text.trim()
            if (text.length > 0) {
              result.strings.push(text)
            }
          }
        }

        return result
      }
    }

    const result = new XPathResult()
    result.nodes = currentNodes
    for (let ni = 0; ni < currentNodes.length; ni++) {
      const text = currentNodes[ni].text.trim()
      if (text.length > 0) {
        result.strings.push(text)
      }
    }
    return result
  }

  private _parsePath(xpath: string): XPathPath {
    const path = new XPathPath()
    const trimmed = xpath.trim()

    if (trimmed === '.') {
      const step = new XPathStep()
      step.stepType = StepType.SELF
      step.axis = AxisType.SELF
      step.nodeTest = '*'
      path.steps.push(step)
      return path
    }

    if (trimmed === '..') {
      const step = new XPathStep()
      step.stepType = StepType.SELF
      step.axis = AxisType.PARENT
      step.nodeTest = '*'
      path.steps.push(step)
      return path
    }

    if (trimmed.startsWith('./') || trimmed.startsWith('.//')) {
      const selfStep = new XPathStep()
      selfStep.stepType = StepType.SELF
      selfStep.axis = AxisType.SELF
      selfStep.nodeTest = '*'
      path.steps.push(selfStep)

      const rest = trimmed.substring(trimmed.startsWith('.//') ? 2 : 1)
      const subPath = this._parsePath(rest)
      for (let i = 0; i < subPath.steps.length; i++) {
        path.steps.push(subPath.steps[i])
      }
      return path
    }

    if (trimmed.startsWith('../') || trimmed.startsWith('..//')) {
      const parentStep = new XPathStep()
      parentStep.stepType = StepType.SELF
      parentStep.axis = AxisType.PARENT
      parentStep.nodeTest = '*'
      path.steps.push(parentStep)

      const rest = trimmed.substring(trimmed.startsWith('..//') ? 3 : 2)
      const subPath = this._parsePath(rest)
      for (let i = 0; i < subPath.steps.length; i++) {
        path.steps.push(subPath.steps[i])
      }
      return path
    }

    const tokens = this._tokenizePath(trimmed)
    let i = 0

    if (i < tokens.length && tokens[i] === '/') {
      i++
    }

    while (i < tokens.length) {
      const step = new XPathStep()

      if (i < tokens.length && tokens[i] === '//') {
        step.stepType = StepType.DESCENDANT
        i++
      } else if (i < tokens.length && tokens[i] === '/') {
        step.stepType = StepType.SELF
        i++
      }

      if (i >= tokens.length) break

      const mainToken = tokens[i]
      i++

      if (mainToken === '.') {
        step.axis = AxisType.SELF
        step.nodeTest = '*'
      } else if (mainToken === '..') {
        step.axis = AxisType.PARENT
        step.nodeTest = '*'
      } else if (mainToken.startsWith('@')) {
        step.axis = AxisType.ATTRIBUTE
        step.nodeTest = mainToken.substring(1)
      } else if (mainToken === 'text()' || mainToken === 'string()') {
        step.func = mainToken
        step.nodeTest = '#text'
      } else if (mainToken === 'node()') {
        step.nodeTest = '#node'
      } else if (mainToken.includes('::')) {
        const colonIdx = mainToken.indexOf('::')
        const axisStr = mainToken.substring(0, colonIdx).toLowerCase()
        step.axis = this._parseAxisName(axisStr)
        const afterAxis = mainToken.substring(colonIdx + 2)
        if (afterAxis.startsWith('@')) {
          step.axis = AxisType.ATTRIBUTE
          step.nodeTest = afterAxis.substring(1)
        } else if (afterAxis === 'text()' || afterAxis === 'string()') {
          step.func = afterAxis
          step.nodeTest = '#text'
        } else {
          step.nodeTest = afterAxis.toLowerCase()
        }
      } else {
        step.nodeTest = mainToken.toLowerCase()
      }

      while (i < tokens.length && tokens[i].startsWith('[')) {
        step.predicates.push(tokens[i].substring(1, tokens[i].length - 1))
        i++
      }

      while (i < tokens.length && tokens[i].startsWith('@') && step.axis !== AxisType.ATTRIBUTE) {
        step.attr = tokens[i].substring(1)
        i++
      }

      if (step.axis === AxisType.CHILD && step.nodeTest === '#text') {
        step.func = 'text()'
      }

      path.steps.push(step)
    }

    return path
  }

  private _tokenizePath(xpath: string): string[] {
    const tokens: string[] = []
    let i = 0
    const len = xpath.length

    while (i < len) {
      while (i < len && (xpath[i] === ' ' || xpath[i] === '\t')) i++
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
        const re: RegExp = /[a-zA-Z0-9_\-:*]/
        while (j < len && re.test(xpath[j])) j++
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
      } else if (xpath[i] === '.') {
        if (i + 1 < len && xpath[i + 1] === '.') {
          tokens.push('..')
          i += 2
        } else {
          tokens.push('.')
          i++
        }
      } else {
        let j = i
        const stopRe: RegExp = /[\[\]\/@\s(]/
        while (j < len && !stopRe.test(xpath[j])) j++
        if (j > i) {
          let token = xpath.substring(i, j)
          if (j < len && xpath[j] === '(') {
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

  private _parseAxisName(name: string): AxisType {
    if (name === 'child') return AxisType.CHILD
    if (name === 'descendant') return AxisType.DESCENDANT
    if (name === 'descendant-or-self') return AxisType.DESCENDANT_OR_SELF
    if (name === 'parent') return AxisType.PARENT
    if (name === 'self') return AxisType.SELF
    if (name === 'ancestor') return AxisType.ANCESTOR
    if (name === 'ancestor-or-self') return AxisType.ANCESTOR_OR_SELF
    if (name === 'following-sibling') return AxisType.FOLLOWING_SIBLING
    if (name === 'preceding-sibling') return AxisType.PRECEDING_SIBLING
    if (name === 'following') return AxisType.FOLLOWING
    if (name === 'preceding') return AxisType.PRECEDING
    if (name === 'attribute') return AxisType.ATTRIBUTE
    return AxisType.CHILD
  }

  private _applyAxis(axis: AxisType, node: HtmlNode): HtmlNode[] {
    if (axis === AxisType.CHILD) {
      return node.elementChildren
    }
    if (axis === AxisType.DESCENDANT) {
      return this._descendant(node)
    }
    if (axis === AxisType.DESCENDANT_OR_SELF) {
      return this._descendantOrSelf(node)
    }
    if (axis === AxisType.PARENT) {
      return node.parentNode ? [node.parentNode] : []
    }
    if (axis === AxisType.SELF) {
      return [node]
    }
    if (axis === AxisType.ANCESTOR) {
      return this._ancestor(node)
    }
    if (axis === AxisType.ANCESTOR_OR_SELF) {
      return this._ancestorOrSelf(node)
    }
    if (axis === AxisType.FOLLOWING_SIBLING) {
      const result: HtmlNode[] = []
      let sibling = node.nextElementSibling
      while (sibling !== null) {
        result.push(sibling)
        sibling = sibling.nextElementSibling
      }
      return result
    }
    if (axis === AxisType.PRECEDING_SIBLING) {
      const result: HtmlNode[] = []
      let sibling = node.previousElementSibling
      while (sibling !== null) {
        result.push(sibling)
        sibling = sibling.previousElementSibling
      }
      return result
    }
    if (axis === AxisType.FOLLOWING) {
      return this._following(node)
    }
    if (axis === AxisType.PRECEDING) {
      return this._preceding(node)
    }
    if (axis === AxisType.ATTRIBUTE) {
      return [node]
    }
    return node.elementChildren
  }

  private _filterByNodeTest(nodes: HtmlNode[], nodeTest: string, axis: AxisType, expandedNode: HtmlNode): HtmlNode[] {
    if (axis === AxisType.ATTRIBUTE) {
      return nodes
    }
    if (nodeTest === '*') {
      return nodes
    }
    if (nodeTest === '#node') {
      if (axis === AxisType.CHILD) {
        const result: HtmlNode[] = []
        const children = expandedNode.childNodes
        for (let j = 0; j < children.length; j++) {
          if (children[j].nodeType === NodeType.ELEMENT) {
            result.push(children[j])
          } else if (children[j].nodeType === NodeType.TEXT && children[j].textContent.trim().length > 0) {
            result.push(children[j])
          }
        }
        return result
      }
      return nodes
    }
    if (nodeTest === '#text') {
      return nodes
    }
    const target = nodeTest.toLowerCase()
    const result: HtmlNode[] = []
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].tagName === target) {
        result.push(nodes[i])
      }
    }
    return result
  }

  private _applyPredicate(nodes: HtmlNode[], predicate: string, expandedNode: HtmlNode): HtmlNode[] {
    const inner = predicate.trim()
    if (inner.length === 0) return nodes

    const posMatch = inner.match(/^(\d+)$/)
    if (posMatch) {
      const pos = parseInt(posMatch[1]) - 1
      return pos >= 0 && pos < nodes.length ? [nodes[pos]] : []
    }

    const lastMatch = inner.match(/^last\(\)$/)
    if (lastMatch) {
      return nodes.length > 0 ? [nodes[nodes.length - 1]] : []
    }

    const lastMinusMatch = inner.match(/^last\(\)\s*-\s*(\d+)$/)
    if (lastMinusMatch) {
      const offset = parseInt(lastMinusMatch[1])
      const idx = nodes.length - 1 - offset
      return idx >= 0 && idx < nodes.length ? [nodes[idx]] : []
    }

    const positionLtMatch = inner.match(/^position\(\)\s*<\s*(\d+)$/)
    if (positionLtMatch) {
      const maxPos = parseInt(positionLtMatch[1])
      const result: HtmlNode[] = []
      for (let idx = 0; idx < nodes.length; idx++) {
        if (idx + 1 < maxPos) result.push(nodes[idx])
      }
      return result
    }

    const positionLeMatch = inner.match(/^position\(\)\s*<=\s*(\d+)$/)
    if (positionLeMatch) {
      const maxPos = parseInt(positionLeMatch[1])
      const result: HtmlNode[] = []
      for (let idx = 0; idx < nodes.length; idx++) {
        if (idx + 1 <= maxPos) result.push(nodes[idx])
      }
      return result
    }

    const positionGtMatch = inner.match(/^position\(\)\s*>\s*(\d+)$/)
    if (positionGtMatch) {
      const minPos = parseInt(positionGtMatch[1])
      const result: HtmlNode[] = []
      for (let idx = 0; idx < nodes.length; idx++) {
        if (idx + 1 > minPos) result.push(nodes[idx])
      }
      return result
    }

    const positionGeMatch = inner.match(/^position\(\)\s*>=\s*(\d+)$/)
    if (positionGeMatch) {
      const minPos = parseInt(positionGeMatch[1])
      const result: HtmlNode[] = []
      for (let idx = 0; idx < nodes.length; idx++) {
        if (idx + 1 >= minPos) result.push(nodes[idx])
      }
      return result
    }

    const positionEqMatch = inner.match(/^position\(\)\s*=\s*(\d+)$/)
    if (positionEqMatch) {
      const pos = parseInt(positionEqMatch[1]) - 1
      return pos >= 0 && pos < nodes.length ? [nodes[pos]] : []
    }

    const attrOpVal = this._matchAttrOperatorValue(inner)
    if (attrOpVal !== null) {
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (this._evalAttrOp(nodes[i], attrOpVal.attr, attrOpVal.op, attrOpVal.val)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const textOpVal = this._matchTextOperatorValue(inner)
    if (textOpVal !== null) {
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (this._evalTextOp(nodes[i], textOpVal.op, textOpVal.val)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const containsAttrMatch = inner.match(/^contains\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (containsAttrMatch) {
      const attrName = containsAttrMatch[1].toLowerCase()
      const substring = containsAttrMatch[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if ((nodes[i].attributes.get(attrName) ?? '').includes(substring)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const containsTextMatch = inner.match(/^contains\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (containsTextMatch) {
      const substring = containsTextMatch[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].text.includes(substring)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const containsConcatClass = inner.match(
      /^contains\(\s*concat\(\s*['"]\s['"]\s*,\s*@class\s*,\s*['"]\s['"]\s*\)\s*,\s*['"]([^'"]+)['"]\s*\)$/
    )
    if (containsConcatClass) {
      const className = containsConcatClass[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        const cls = ' ' + (nodes[i].attributes.get('class') ?? '') + ' '
        if (cls.includes(' ' + className + ' ')) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const startsWithAttr = inner.match(/^starts-with\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (startsWithAttr) {
      const attrName = startsWithAttr[1].toLowerCase()
      const prefix = startsWithAttr[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if ((nodes[i].attributes.get(attrName) ?? '').startsWith(prefix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const startsWithText = inner.match(/^starts-with\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (startsWithText) {
      const prefix = startsWithText[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].text.startsWith(prefix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const endsWithAttr = inner.match(/^ends-with\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (endsWithAttr) {
      const attrName = endsWithAttr[1].toLowerCase()
      const suffix = endsWithAttr[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if ((nodes[i].attributes.get(attrName) ?? '').endsWith(suffix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const endsWithText = inner.match(/^ends-with\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)$/)
    if (endsWithText) {
      const suffix = endsWithText[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].text.endsWith(suffix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const notContainsAttr = inner.match(/^not\(\s*contains\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)$/)
    if (notContainsAttr) {
      const attrName = notContainsAttr[1].toLowerCase()
      const substring = notContainsAttr[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!(nodes[i].attributes.get(attrName) ?? '').includes(substring)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const notContainsText = inner.match(/^not\(\s*contains\(\s*text\(\)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)$/)
    if (notContainsText) {
      const substring = notContainsText[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!nodes[i].text.includes(substring)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const notStartsWithAttr = inner.match(/^not\(\s*starts-with\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)$/)
    if (notStartsWithAttr) {
      const attrName = notStartsWithAttr[1].toLowerCase()
      const prefix = notStartsWithAttr[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!(nodes[i].attributes.get(attrName) ?? '').startsWith(prefix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const notEndsWithAttr = inner.match(/^not\(\s*ends-with\(\s*@([a-zA-Z0-9_\-]+)\s*,\s*['"]([^'"]*)['"]\s*\)\s*\)$/)
    if (notEndsWithAttr) {
      const attrName = notEndsWithAttr[1].toLowerCase()
      const suffix = notEndsWithAttr[2]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!(nodes[i].attributes.get(attrName) ?? '').endsWith(suffix)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const notAttrOpVal = this._matchNotAttrOperatorValue(inner)
    if (notAttrOpVal !== null) {
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!this._evalAttrOp(nodes[i], notAttrOpVal.attr, notAttrOpVal.op, notAttrOpVal.val)) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const textMatch = inner.match(/^text\(\)\s*=\s*['"]([^'"]*)['"]$/)
    if (textMatch) {
      const val = textMatch[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].text.trim() === val) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const textNeMatch = inner.match(/^text\(\)\s*!=\s*['"]([^'"]*)['"]$/)
    if (textNeMatch) {
      const val = textNeMatch[1]
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (nodes[i].text.trim() !== val) {
          result.push(nodes[i])
        }
      }
      return result
    }

    const andSplit = this._splitLogical(inner, ' and ')
    if (andSplit !== null) {
      const left = this._applyPredicate(nodes, andSplit.left, expandedNode)
      const leftSet = new Set<HtmlNode>()
      for (let i = 0; i < left.length; i++) leftSet.add(left[i])
      const right = this._applyPredicate(nodes, andSplit.right, expandedNode)
      const result: HtmlNode[] = []
      for (let i = 0; i < right.length; i++) {
        if (leftSet.has(right[i])) result.push(right[i])
      }
      return result
    }

    const orSplit = this._splitLogical(inner, ' or ')
    if (orSplit !== null) {
      const left = this._applyPredicate(nodes, orSplit.left, expandedNode)
      const right = this._applyPredicate(nodes, orSplit.right, expandedNode)
      const leftSet = new Set<HtmlNode>()
      for (let i = 0; i < left.length; i++) leftSet.add(left[i])
      const combined: HtmlNode[] = []
      for (let i = 0; i < left.length; i++) combined.push(left[i])
      for (let i = 0; i < right.length; i++) {
        if (!leftSet.has(right[i])) combined.push(right[i])
      }
      return combined
    }

    const notPredicate = this._matchNotPredicate(inner)
    if (notPredicate !== null) {
      const excluded = this._applyPredicate(nodes, notPredicate, expandedNode)
      const excludeSet = new Set<HtmlNode>()
      for (let i = 0; i < excluded.length; i++) excludeSet.add(excluded[i])
      const result: HtmlNode[] = []
      for (let i = 0; i < nodes.length; i++) {
        if (!excludeSet.has(nodes[i])) result.push(nodes[i])
      }
      return result
    }

    return nodes
  }

  private _matchAttrOperatorValue(inner: string): AttrOpVal | null {
    const re: RegExp = /^@([a-zA-Z0-9_\-]+)\s*(=~|\|=|\^=|\$=|\*=|!=|=)\s*['"]([^'"]*)['"]$/
    const m = inner.match(re)
    if (m) {
      const result = new AttrOpVal()
      result.attr = m[1].toLowerCase()
      result.op = m[2]
      result.val = m[3]
      return result
    }
    return null
  }

  private _matchNotAttrOperatorValue(inner: string): AttrOpVal | null {
    const re: RegExp = /^not\(\s*@([a-zA-Z0-9_\-]+)\s*(=~|\|=|\^=|\$=|\*=|!=|=)\s*['"]([^'"]*)['"]\s*\)$/
    const m = inner.match(re)
    if (m) {
      const result = new AttrOpVal()
      result.attr = m[1].toLowerCase()
      result.op = m[2]
      result.val = m[3]
      return result
    }
    return null
  }

  private _matchTextOperatorValue(inner: string): TextOpVal | null {
    const re: RegExp = /^text\(\)\s*(=~|\|=|\^=|\$=|\*=|!=|=)\s*['"]([^'"]*)['"]$/
    const m = inner.match(re)
    if (m) {
      const result = new TextOpVal()
      result.op = m[1]
      result.val = m[2]
      return result
    }
    return null
  }

  private _evalAttrOp(node: HtmlNode, attr: string, op: string, val: string): boolean {
    const actual = node.attributes.get(attr) ?? ''
    if (op === '=') return actual === val
    if (op === '!=') return actual !== val
    if (op === '~=') {
      const parts = actual.split(/\s+/)
      for (let i = 0; i < parts.length; i++) {
        if (parts[i] === val) return true
      }
      return false
    }
    if (op === '^=') return actual.startsWith(val)
    if (op === '$=') return actual.endsWith(val)
    if (op === '*=') return actual.includes(val)
    if (op === '|=') return actual === val || actual.startsWith(val + '-')
    return actual === val
  }

  private _evalTextOp(node: HtmlNode, op: string, val: string): boolean {
    const actual = node.text.trim()
    if (op === '=') return actual === val
    if (op === '!=') return actual !== val
    if (op === '~=') {
      const parts = actual.split(/\s+/)
      for (let i = 0; i < parts.length; i++) {
        if (parts[i] === val) return true
      }
      return false
    }
    if (op === '^=') return actual.startsWith(val)
    if (op === '$=') return actual.endsWith(val)
    if (op === '*=') return actual.includes(val)
    if (op === '|=') return actual === val || actual.startsWith(val + '-')
    return actual === val
  }

  private _matchNotPredicate(inner: string): string | null {
    const re: RegExp = /^not\(\s*(.+)\s*\)$/
    const m = inner.match(re)
    if (m) {
      const content = m[1].trim()
      if (!content.includes(' and ') && !content.includes(' or ')) {
        return content
      }
    }
    return null
  }

  private _splitLogical(inner: string, operator: string): LogicalSplit | null {
    const lower = inner.toLowerCase()
    let depth = 0
    let bestPos = -1

    for (let i = 0; i < lower.length; i++) {
      if (inner[i] === '(') depth++
      else if (inner[i] === ')') depth--
      else if (inner[i] === '[') depth++
      else if (inner[i] === ']') depth--
      else if (inner[i] === '"' || inner[i] === "'") {
        const quote = inner[i]
        i++
        while (i < lower.length && inner[i] !== quote) i++
      } else if (depth === 0 && i + operator.length <= lower.length) {
        const segment = lower.substring(i, i + operator.length)
        if (segment === operator && bestPos === -1) {
          bestPos = i
        }
      }
    }

    if (bestPos === -1) return null

    const result = new LogicalSplit()
    result.left = inner.substring(0, bestPos).trim()
    result.right = inner.substring(bestPos + operator.length).trim()
    return result
  }

  private _descendantOrSelf(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = [node]
    this._collectDescendants(node, result)
    return result
  }

  private _descendant(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = []
    this._collectDescendants(node, result)
    return result
  }

  private _collectDescendants(node: HtmlNode, result: HtmlNode[]): void {
    const children = node.elementChildren
    for (let i = 0; i < children.length; i++) {
      result.push(children[i])
      this._collectDescendants(children[i], result)
    }
  }

  private _ancestor(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = []
    let current = node.parentNode
    while (current !== null) {
      result.push(current)
      current = current.parentNode
    }
    return result
  }

  private _ancestorOrSelf(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = [node]
    let current = node.parentNode
    while (current !== null) {
      result.push(current)
      current = current.parentNode
    }
    return result
  }

  private _documentRoot(node: HtmlNode): HtmlNode {
    let current = node
    while (current.parentNode !== null) {
      current = current.parentNode
    }
    return current
  }

  private _following(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = []
    let current: HtmlNode | null = node
    while (current !== null) {
      const sibling: HtmlNode | null = current.nextElementSibling
      if (sibling !== null) {
        result.push(sibling)
        this._collectDescendants(sibling, result)
        current = sibling
      } else {
        current = current.parentNode
      }
    }
    return result
  }

  private _preceding(node: HtmlNode): HtmlNode[] {
    const result: HtmlNode[] = []
    let current: HtmlNode | null = node
    while (current !== null) {
      const sibling: HtmlNode | null = current.previousElementSibling
      if (sibling !== null) {
        this._collectDescendantsAndSelfReversed(sibling, result)
        current = sibling
      } else {
        current = current.parentNode
      }
    }
    return result
  }

  private _collectDescendantsAndSelfReversed(node: HtmlNode, result: HtmlNode[]): void {
    const children = node.elementChildren
    for (let i = children.length - 1; i >= 0; i--) {
      this._collectDescendantsAndSelfReversed(children[i], result)
    }
    result.push(node)
  }
}
