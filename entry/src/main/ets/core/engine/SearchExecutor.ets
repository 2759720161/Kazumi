import { HtmlXPathParser } from './HtmlXPathParser';
import { HtmlDocument, HtmlNode, NodeType } from './HtmlParser';
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel';
import { AnimeItem } from '../../models/AnimeItem';
import { Episode } from '../../models/Episode';
import { PlaybackRoad } from '../../models/PlaybackRoad';
import { Logger } from '../../utils/Logger';

const logger = new Logger('SearchExecutor');

export class SearchExecutor {
  private parser: HtmlXPathParser;

  constructor() {
    this.parser = new HtmlXPathParser();
  }

  parseSearchResults(html: string, runtime: RuleRuntimeModel): AnimeItem[] {
    const items: AnimeItem[] = [];
    try {
      logger.info('Search html length=%{public}d, hasListClass=%{public}s',
        html.length, String(html.includes('public-list-box')));
      const doc: HtmlDocument = this.parser.parse(html);
      let listNodes = this.parser.selectNodes(runtime.rule.searchList, doc);
      if (listNodes.length === 0) {
        listNodes = this.selectFallbackSearchNodes(doc);
        if (listNodes.length === 0) {
          logger.warn('No search list nodes found for rule: %{public}s, xpath=%{public}s, htmlHead=%{public}s',
            runtime.rule.name, runtime.rule.searchList, html.substring(0, 200));
          return items;
        }
        logger.info('Using fallback search list parser for rule %{public}s, nodes=%{public}d',
          runtime.rule.name, listNodes.length);
      }

      for (let i = 0; i < listNodes.length; i++) {
        try {
          const node = listNodes[i];
          const item = new AnimeItem();
          item.sourceName = runtime.rule.name;
          item.sourceId = runtime.rule.id;

          item.name = this.selectFirstText(runtime.rule.searchName, node);
          if (item.name.length === 0) {
            item.name = this.selectFallbackName(node);
          }

          let resultText = this.selectFirstLink(runtime.rule.searchResult, node);
          if (resultText.length === 0) {
            resultText = this.selectFallbackLink(node);
          }
          if (resultText.length > 0) {
            item.url = this.resolvePageUrl(resultText, runtime);
          }

          const coverText = this.selectFirstImage(node);
          if (coverText.length > 0) {
            const resolvedUrl = this.resolveImageUrl(coverText, runtime);
            const fallbackUrl = this.extractFallbackUrl(resolvedUrl);
            if (fallbackUrl.length > 0) {
              if (this.needsProxy(fallbackUrl)) {
                item.cover = resolvedUrl;
                item.coverFallback = fallbackUrl;
              } else {
                item.cover = fallbackUrl;
                item.coverFallback = resolvedUrl;
              }
            } else {
              item.cover = resolvedUrl;
              item.coverFallback = '';
            }
          }

          logger.info('Search item[%{public}d]: name=%{public}s, coverLen=%{public}d, coverPrefix=%{public}s',
            i, item.name, item.cover.length,
            item.cover.length > 80 ? item.cover.substring(0, 80) : item.cover);

          if (item.name.length > 0 && item.url.length > 0) {
            items.push(item);
          }
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          logger.warn('Failed to parse search item %{public}d: %{public}s', i, msg);
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Search parsing failed for rule %{public}s: %{public}s', runtime.rule.name, msg);
    }
    return items;
  }

  private selectFallbackSearchNodes(doc: HtmlDocument): HtmlNode[] {
    const candidates: string[] = [
      "//div[contains(@class,'cata_video_item')]",
      "//div[contains(@class,'public-list-box') and contains(@class,'search-box')]",
      "//div[contains(@class,'module-card-item')]",
      "//li[contains(@class,'video-item')]",
      "//li[contains(@class,'search-item')]"
    ];
    for (let i = 0; i < candidates.length; i++) {
      const nodes = this.parser.selectNodes(candidates[i], doc);
      if (nodes.length > 0) {
        return nodes;
      }
    }
    return [];
  }

  private selectFallbackName(context: HtmlDocument | HtmlNode): string {
    const candidates: string[] = [
      ".//h5[contains(@class,'card-title')]/a/text()",
      ".//a/@title",
      ".//img/@alt",
      ".//div[contains(@class,'thumb-txt')]/text()",
      ".//a[contains(@class,'time-title')]/text()",
      ".//h3/text()",
      ".//h2/text()"
    ];
    for (let i = 0; i < candidates.length; i++) {
      const value = this.selectFirstText(candidates[i], context);
      if (value.length > 0) {
        return this.cleanFallbackName(value);
      }
    }
    return '';
  }

  private selectFallbackLink(context: HtmlDocument | HtmlNode): string {
    const candidates: string[] = [
      ".//h5[contains(@class,'card-title')]/a/@href",
      ".//a[contains(@href,'/detail/')]/@href",
      ".//a[contains(@class,'public-list-exp')]/@href",
      ".//a/@href"
    ];
    for (let i = 0; i < candidates.length; i++) {
      const value = this.selectFirstLink(candidates[i], context);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private cleanFallbackName(name: string): string {
    let value = name.trim();
    const suffixes: string[] = ['封面图', '海报图片', '海报图'];
    for (let i = 0; i < suffixes.length; i++) {
      if (value.endsWith(suffixes[i])) {
        value = value.substring(0, value.length - suffixes[i].length).trim();
      }
    }
    return value;
  }

  private selectFirstText(xpath: string, context: HtmlDocument | HtmlNode): string {
    const result = this.parser.evaluate(xpath, context);
    if (result.strings.length > 0) {
      return result.strings[0].trim();
    }
    if (result.nodes.length > 0) {
      return this.getTextContent(result.nodes[0]).trim();
    }
    return '';
  }

  private selectFirstLink(xpath: string, context: HtmlDocument | HtmlNode): string {
    const result = this.parser.evaluate(xpath, context);
    if (result.strings.length > 0) {
      return result.strings[0].trim();
    }
    if (result.nodes.length > 0) {
      const node = result.nodes[0];
      const href = node.attributes.get('href') ?? '';
      if (href.length > 0) {
        return href.trim();
      }
      return this.getTextContent(node).trim();
    }
    return '';
  }

  private selectFirstImage(context: HtmlDocument | HtmlNode): string {
    const candidates: string[] = [
      './/img/@data-src',
      './/img/@data-original',
      './/img/@src',
      ".//div[contains(@class,'cover')]/@style"
    ];

    for (let i = 0; i < candidates.length; i++) {
      const value = this.selectFirstString(candidates[i], context);
      if (value.length === 0 || value.startsWith('data:')) {
        continue;
      }
      if (candidates[i].endsWith('/@style')) {
        return this.extractUrlFromStyle(value);
      }
      return value;
    }

    return '';
  }

  private selectFirstString(xpath: string, context: HtmlDocument | HtmlNode): string {
    const result = this.parser.evaluate(xpath, context);
    if (result.strings.length > 0) {
      return result.strings[0].trim();
    }
    return '';
  }

  private extractUrlFromStyle(style: string): string {
    const urlStart = style.indexOf('url(');
    if (urlStart === -1) {
      return '';
    }

    const valueStart = urlStart + 4;
    const valueEnd = style.indexOf(')', valueStart);
    if (valueEnd === -1) {
      return '';
    }

    let value = style.substring(valueStart, valueEnd).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  private resolveImageUrl(url: string, runtime: RuleRuntimeModel): string {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:' + url;
    }
    return runtime.buildFullUrl(url);
  }

  private resolvePageUrl(url: string, runtime: RuleRuntimeModel): string {
    const resolved = runtime.buildFullUrl(url);
    return this.normalizeSameHostHttpUrl(resolved, runtime.rule.baseUrl);
  }

  private normalizeSameHostHttpUrl(url: string, baseUrl: string): string {
    if (!url.startsWith('http://') || !baseUrl.startsWith('https://')) {
      return url;
    }

    const urlHost = this.extractHost(url);
    const baseHost = this.extractHost(baseUrl);
    if (urlHost.length > 0 && urlHost === baseHost) {
      return 'https://' + url.substring('http://'.length);
    }
    return url;
  }

  private extractHost(url: string): string {
    let value = url;
    const schemeIndex = value.indexOf('://');
    if (schemeIndex !== -1) {
      value = value.substring(schemeIndex + 3);
    }

    const slashIndex = value.indexOf('/');
    if (slashIndex !== -1) {
      value = value.substring(0, slashIndex);
    }

    const colonIndex = value.indexOf(':');
    if (colonIndex !== -1) {
      value = value.substring(0, colonIndex);
    }
    return value.toLowerCase();
  }

  private extractFallbackUrl(coverUrl: string): string {
    if (coverUrl.length === 0) {
      return '';
    }
    const proxyPatterns: string[] = [
      '/img.php?url=',
      '/image.php?url=',
      '/proxy?url=',
      '/pic?url='
    ];
    for (let i = 0; i < proxyPatterns.length; i++) {
      const idx = coverUrl.indexOf(proxyPatterns[i]);
      if (idx !== -1) {
        const rawUrl = coverUrl.substring(idx + proxyPatterns[i].length).split('&')[0];
        if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          return decodeURIComponent(rawUrl);
        }
      }
    }
    return '';
  }

  private needsProxy(url: string): boolean {
    const antiHotlinkDomains: string[] = [
      'doubanio.com',
      'douban.com',
      'imgdb.cn'
    ];
    for (let i = 0; i < antiHotlinkDomains.length; i++) {
      if (url.includes(antiHotlinkDomains[i])) {
        return true;
      }
    }
    return false;
  }

  private getTextContent(node: HtmlNode): string {
    if (node.nodeType === NodeType.TEXT) {
      return node.textContent;
    }

    let text = '';
    for (let i = 0; i < node.childNodes.length; i++) {
      text += this.getTextContent(node.childNodes[i]);
    }
    return text;
  }

  parseDetail(html: string, runtime: RuleRuntimeModel): Record<string, string> {
    const detail: Record<string, string> = {};
    try {
      if (runtime.rule.chapterRoads.length > 0) {
        const doc: HtmlDocument = this.parser.parse(html);
        const nodes = this.parser.select(runtime.rule.chapterRoads, doc);
        if (nodes.length > 0) {
          detail['chapterRoadsHtml'] = nodes[0];
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Detail parsing failed: %{public}s', msg);
    }
    return detail;
  }

  parseEpisodes(html: string, runtime: RuleRuntimeModel): Episode[] {
    const episodes: Episode[] = [];
    try {
      const doc: HtmlDocument = this.parser.parse(html);
      const listNodes = this.parser.selectNodes(runtime.rule.chapterRoads, doc);
      if (listNodes.length === 0) {
        logger.warn('No episode list nodes found for rule: %{public}s, xpath=%{public}s',
          runtime.rule.name, runtime.rule.chapterRoads);
        return episodes;
      }

      for (let i = 0; i < listNodes.length; i++) {
        try {
          const node = listNodes[i];
          const episode = new Episode();
          episode.index = i;

          episode.name = this.selectFirstText(runtime.rule.chapterResult, node);

          const resultText = this.selectFirstLink(runtime.rule.chapterResult, node);
          if (resultText.length > 0) {
            episode.url = this.resolvePageUrl(resultText, runtime);
          }

          if (episode.name.length === 0) {
            episode.name = `第${i + 1}集`;
          }

          episodes.push(episode);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          logger.warn('Failed to parse episode %{public}d: %{public}s', i, msg);
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Episode parsing failed for rule %{public}s: %{public}s', runtime.rule.name, msg);
    }
    return episodes;
  }

  parseRoads(html: string, runtime: RuleRuntimeModel): PlaybackRoad[] {
    const roads: PlaybackRoad[] = [];
    try {
      const doc: HtmlDocument = this.parser.parse(html);
      let roadNodes = this.parser.selectNodes(runtime.rule.chapterRoads, doc);
      if (roadNodes.length === 0) {
        roadNodes = this.selectFallbackRoadNodes(doc);
        if (roadNodes.length === 0) {
          logger.warn('No road nodes found for rule: %{public}s, xpath=%{public}s',
            runtime.rule.name, runtime.rule.chapterRoads);
          return roads;
        }
        logger.info('Using fallback road parser for rule %{public}s, nodes=%{public}d, xpath=%{public}s',
          runtime.rule.name, runtime.rule.chapterRoads);
      }

      if (this.isDirectEpisodeMode(runtime, roadNodes)) {
        logger.info('Rule %{public}s uses direct-episode mode, merging all nodes into one road',
          runtime.rule.name);
        const episodeNames: string[] = [];
        const episodeUrls: string[] = [];
        for (let i = 0; i < roadNodes.length; i++) {
          const node = roadNodes[i];
          let epName = this.getTextContent(node).trim();
          if (epName.length === 0) {
            epName = `第${i + 1}集`;
          }
          const href = node.attributes.get('href') ?? '';
          let epUrl = '';
          if (href.length > 0) {
            epUrl = this.resolvePageUrl(href, runtime);
          }
          episodeNames.push(epName);
          episodeUrls.push(epUrl);
        }
        const road = PlaybackRoad.create('播放列表', episodeNames, episodeUrls,
          runtime.rule.id, runtime.rule.name, '');
        roads.push(road);
        logger.info('Direct-episode road: episodes=%{public}d', episodeNames.length);
        return roads;
      }

      for (let i = 0; i < roadNodes.length; i++) {
        try {
          const roadNode = roadNodes[i];
          const episodeNodes = this.parser.selectNodes(runtime.rule.chapterResult, roadNode);
          if (episodeNodes.length === 0) {
            logger.debug('Road %{public}d has no episodes, skipping', i);
            continue;
          }

          const roadName = this.extractRoadName(roadNode, i);
          const episodeNames: string[] = [];
          const episodeUrls: string[] = [];

          for (let j = 0; j < episodeNodes.length; j++) {
            const epNode = episodeNodes[j];
            let epName = this.getTextContent(epNode).trim();
            if (epName.length === 0) {
              epName = `第${j + 1}集`;
            }
            const href = epNode.attributes.get('href') ?? '';
            let epUrl = '';
            if (href.length > 0) {
              epUrl = this.resolvePageUrl(href, runtime);
            }
            episodeNames.push(epName);
            episodeUrls.push(epUrl);
          }

          const road = PlaybackRoad.create(roadName, episodeNames, episodeUrls,
            runtime.rule.id, runtime.rule.name, '');
          roads.push(road);
          logger.info('Road %{public}d: name=%{public}s, episodes=%{public}d',
            i, roadName, episodeNodes.length);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          logger.warn('Failed to parse road %{public}d: %{public}s', i, msg);
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Road parsing failed for rule %{public}s: %{public}s', runtime.rule.name, msg);
    }
    return roads;
  }

  private selectFallbackRoadNodes(doc: HtmlDocument): HtmlNode[] {
    const roadCandidates: string[] = [
      "//div[contains(@class,'tab-pane')]",
      "//div[contains(@class,'video_detail_playlist_wrapper')]",
      "//div[contains(@class,'playlist')]",
      "//ul[contains(@class,'playlist')]",
      "//ul[contains(@class,'play')]"
    ];
    for (let i = 0; i < roadCandidates.length; i++) {
      const nodes = this.parser.selectNodes(roadCandidates[i], doc);
      const filtered = this.filterNodesWithPlaybackLinks(nodes);
      if (filtered.length > 0) {
        return filtered;
      }
    }
    return [];
  }

  private filterNodesWithPlaybackLinks(nodes: HtmlNode[]): HtmlNode[] {
    const result: HtmlNode[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const links = this.parser.selectNodes(".//a[contains(@href,'/play/')]", nodes[i]);
      if (links.length > 0) {
        result.push(nodes[i]);
      }
    }
    return result;
  }

  private isDirectEpisodeMode(runtime: RuleRuntimeModel, roadNodes: HtmlNode[]): boolean {
    if (runtime.rule.chapterResult === '.') {
      return true;
    }
    let anchorCount = 0;
    for (let i = 0; i < roadNodes.length; i++) {
      if (roadNodes[i].tagName === 'a') {
        anchorCount++;
      }
    }
    if (roadNodes.length > 0 && anchorCount === roadNodes.length) {
      return true;
    }
    return false;
  }

  private extractRoadName(node: HtmlNode, index: number): string {
    const tagCandidates: string[] = [
      ".//span/text()",
      ".//h3/text()",
      ".//h4/text()",
      ".//div[contains(@class,'module-heading')]/text()",
      ".//div[contains(@class,'title')]/text()"
    ];
    for (let i = 0; i < tagCandidates.length; i++) {
      const text = this.selectFirstText(tagCandidates[i], node);
      if (text.length > 0) {
        return text;
      }
    }
    return `线路${index + 1}`;
  }
}
