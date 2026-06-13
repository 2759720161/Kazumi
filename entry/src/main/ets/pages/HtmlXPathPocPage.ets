import { HtmlParser, HtmlDocument } from '../core/engine/HtmlParser'
import { XPathEvaluator } from '../core/engine/XPathEvaluator'
import { HtmlXPathParser } from '../core/engine/HtmlXPathParser'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000
const TAG = 'HtmlXPathPoc'

@Entry
@Component
struct HtmlXPathPocPage {
  @State testResults: string[] = []
  @State summary: string = '运行中...'

  build() {
    Scroll() {
      Column() {
        Text('T0.1 HTML/XPath 解析 POC')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })

        Button('运行全部测试')
          .onClick(() => this.runAllTests())
          .backgroundColor('#D9007DFF')
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: '#4DFFFFFF' })
          .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
          .margin({ bottom: 16 })

        Text(this.summary)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })

        ForEach(this.testResults, (result: string, index: number) => {
          Text(result)
            .fontSize(12)
            .fontFamily('monospace')
            .width('100%')
            .margin({ bottom: 2 })
        }, (result: string, index: number) => `${index}`)
      }
      .padding(16)
      .width('100%')
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background('#FFFFFF')
    .ignoreLayoutSafeArea()
  }

  private addResult(text: string): void {
    this.testResults.push(text)
    hilog.info(DOMAIN, TAG, '%{public}s', text)
  }

  private runAllTests(): void {
    this.testResults = []
    let passed = 0
    let total = 0

    this.addResult('--- 调试: DOM结构检查 ---')
    const debugHtml = '<div class="container"><h1>标题</h1><p>段落1</p><p>段落2</p></div>'
    const debugParser = new HtmlXPathParser()
    const debugDoc = debugParser.parse(debugHtml)
    this.addResult(`  root.tagName=${debugDoc.root?.tagName}, children=${debugDoc.root?.childNodes.length}`)
    if (debugDoc.root) {
      for (const child of debugDoc.root.childNodes) {
        this.addResult(`    child: tag=${child.tagName}, type=${child.nodeType}, children=${child.childNodes.length}`)
        for (const grand of child.childNodes) {
          this.addResult(`      grand: tag=${grand.tagName}, type=${grand.nodeType}, text="${grand.textContent.substring(0, 20)}", children=${grand.childNodes.length}`)
        }
      }
    }

    const test1 = this.testBasicHtmlParsing()
    total++; if (test1) passed++

    const test2 = this.testXPathAttributeSelect()
    total++; if (test2) passed++

    const test3 = this.testXPathTextSelect()
    total++; if (test3) passed++

    const test4 = this.testXPathPositionPredicate()
    total++; if (test4) passed++

    const test5 = this.testXPathContainsPredicate()
    total++; if (test5) passed++

    const test6 = this.testNestedElements()
    total++; if (test6) passed++

    const test7 = this.testSearchListXPath()
    total++; if (test7) passed++

    const test8 = this.testChapterRoadsXPath()
    total++; if (test8) passed++

    this.summary = `测试完成: ${passed}/${total} 通过 (${Math.round(passed / total * 100)}%)`
  }

  private testBasicHtmlParsing(): boolean {
    this.addResult('--- 测试1: 基础HTML解析 ---')
    const html = '<div class="container"><h1>标题</h1><p>段落1</p><p>段落2</p></div>'
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const result = parser.select('//p/text()', doc)
    const pass = result.length === 2 && result[0] === '段落1' && result[1] === '段落2'
    this.addResult(`  //p/text() => [${result.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testXPathAttributeSelect(): boolean {
    this.addResult('--- 测试2: XPath属性选择 ---')
    const html = '<a href="/detail/1" class="link">番剧1</a><a href="/detail/2">番剧2</a>'
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const hrefs = parser.select('//a/@href', doc)
    const pass = hrefs.length === 2 && hrefs[0] === '/detail/1' && hrefs[1] === '/detail/2'
    this.addResult(`  //a/@href => [${hrefs.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testXPathTextSelect(): boolean {
    this.addResult('--- 测试3: XPath文本选择 ---')
    const html = '<ul><li>进击的巨人</li><li>鬼灭之刃</li><li>咒术回战</li></ul>'
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const texts = parser.select('//li/text()', doc)
    const pass = texts.length === 3
    this.addResult(`  //li/text() => [${texts.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testXPathPositionPredicate(): boolean {
    this.addResult('--- 测试4: XPath位置谓词 ---')
    const html = '<div><span>A</span><span>B</span><span>C</span></div>'
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const first = parser.selectFirst('//span[1]/text()', doc)
    const second = parser.selectFirst('//span[2]/text()', doc)
    const pass = first === 'A' && second === 'B'
    this.addResult(`  //span[1] => ${first}, //span[2] => ${second} ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testXPathContainsPredicate(): boolean {
    this.addResult('--- 测试5: XPath contains谓词 ---')
    const html = '<div class="item active">A</div><div class="item">B</div>'
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const result = parser.select('//div[@class="item active"]/text()', doc)
    const pass = result.length === 1 && result[0] === 'A'
    this.addResult(`  //div[@class="item active"]/text() => [${result.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testNestedElements(): boolean {
    this.addResult('--- 测试6: 嵌套元素解析 ---')
    const html = `<div class="search-result">
      <a href="/anime/1" class="name"><span>进击的巨人</span></a>
      <img src="cover1.jpg" class="cover"/>
      <a href="/anime/2" class="name"><span>鬼灭之刃</span></a>
      <img src="cover2.jpg" class="cover"/>
    </div>`
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const names = parser.select('//a[@class="name"]/span/text()', doc)
    const covers = parser.select('//img[@class="cover"]/@src', doc)
    const pass = names.length === 2 && covers.length === 2
    this.addResult(`  names: [${names.join(', ')}], covers: [${covers.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testSearchListXPath(): boolean {
    this.addResult('--- 测试7: searchList XPath模式 ---')
    const html = `<ul class="search-list">
      <li><a href="/play/1" title="E1">第1集</a></li>
      <li><a href="/play/2" title="E2">第2集</a></li>
      <li><a href="/play/3" title="E3">第3集</a></li>
    </ul>`
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const urls = parser.select('//ul[@class="search-list"]//a/@href', doc)
    const titles = parser.select('//ul[@class="search-list"]//a/@title', doc)
    const pass = urls.length === 3 && titles.length === 3
    this.addResult(`  urls: [${urls.join(', ')}], titles: [${titles.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }

  private testChapterRoadsXPath(): boolean {
    this.addResult('--- 测试8: chapterRoads XPath模式 ---')
    const html = `<div class="playlist">
      <div class="road">
        <h3>线路1</h3>
        <a href="/e1">EP1</a>
        <a href="/e2">EP2</a>
      </div>
      <div class="road">
        <h3>线路2</h3>
        <a href="/f1">EP1</a>
      </div>
    </div>`
    const parser = new HtmlXPathParser()
    const doc = parser.parse(html)
    const roads = parser.selectNodes('//div[@class="road"]', doc)
    const roadNames = parser.select('//div[@class="road"]/h3/text()', doc)
    const allLinks = parser.select('//div[@class="road"]//a/@href', doc)
    const pass = roads.length === 2 && roadNames.length === 2 && allLinks.length === 3
    this.addResult(`  roads: ${roads.length}, names: [${roadNames.join(', ')}], links: [${allLinks.join(', ')}] ${pass ? '✅' : '❌'}`)
    return pass
  }
}
