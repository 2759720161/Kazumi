import { HtmlParser, HtmlDocument, HtmlNode } from './HtmlParser'
import { XPathEvaluator, XPathResult } from './XPathEvaluator'

export class HtmlXPathParser {
  private parser: HtmlParser = new HtmlParser()
  private evaluator: XPathEvaluator = new XPathEvaluator()

  parse(html: string): HtmlDocument {
    return this.parser.parse(html)
  }

  evaluate(xpath: string, context: HtmlDocument | HtmlNode): XPathResult {
    return this.evaluator.evaluate(xpath, context)
  }

  select(xpath: string, context: HtmlDocument | HtmlNode): string[] {
    return this.evaluator.selectStrings(xpath, context)
  }

  selectFirst(xpath: string, context: HtmlDocument | HtmlNode): string {
    const results = this.select(xpath, context)
    return results.length > 0 ? results[0] : ''
  }

  selectNodes(xpath: string, context: HtmlDocument | HtmlNode): HtmlNode[] {
    return this.evaluator.select(xpath, context)
  }
}
