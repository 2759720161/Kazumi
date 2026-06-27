import { HtmlXPathParser } from './HtmlXPathParser';
import { HtmlDocument, HtmlNode, NodeType } from './HtmlParser';
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel';
import { AnimeItem } from '../../models/AnimeItem';
import { Episode } from '../../models/Episode';
import { PlaybackRoad } from '../../models/PlaybackRoad';
import { SearchResultFilter } from './SearchResultFilter';
import { Logger } from '../../utils/Logger';

const logger = new Logger('SearchExecutor');

export class SearchExecutor {
  private parser: HtmlXPathParser;
  private searchResultFilter: SearchResultFilter;

  constructor() {
    this.parser = new HtmlXPathParser();
    this.searchResultFilter = new SearchResultFilter();
  }

  parseSearchResults(html: string, runtime: RuleRuntimeModel): AnimeItem[] {
    const items: AnimeItem[] = [];
    try {
      logger.info('Search html length=%{public}d, hasListClass=%{public}s',
        html.length, String(html.includes('public-list-box')));
      const doc: HtmlDocument = this.parser.parse(html);
      if (runtime.rule.name.toLowerCase() === '7sefun') {
        return this.parse7sefunSearchResults(doc, runtime);
      }
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

      this.appendSearchItems(items, listNodes, runtime, 'Search item');

      const filtered = this.searchResultFilter.filterAndDeduplicate(items, runtime.rule.name);
      if (filtered.length > 0 || items.length === 0) {
        return filtered;
      }

      const fallbackNodes = this.selectFallbackSearchNodes(doc);
      if (fallbackNodes.length > 0) {
        const fallbackItems: AnimeItem[] = [];
        this.appendSearchItems(fallbackItems, fallbackNodes, runtime, 'Fallback search item');
        const fallbackFiltered = this.searchResultFilter.filterAndDeduplicate(fallbackItems, runtime.rule.name);
        if (fallbackFiltered.length > 0) {
          logger.info('Search rule %{public}s recovered by fallback parser: nodes=%{public}d, valid=%{public}d',
            runtime.rule.name, fallbackNodes.length, fallbackFiltered.length);
          return fallbackFiltered;
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Search parsing failed for rule %{public}s: %{public}s', runtime.rule.name, msg);
    }
    return [];
  }

  private parse7sefunSearchResults(doc: HtmlDocument, runtime: RuleRuntimeModel): AnimeItem[] {
    const nodes = this.parser.selectNodes("//div[contains(@class,'module-search-item')]", doc);
    if (nodes.length === 0) {
      return [];
    }

    const items: AnimeItem[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const item = new AnimeItem();
      item.sourceName = runtime.rule.name;
      item.sourceId = runtime.rule.id;

      const detailAnchor = this.find7sefunDetailAnchor(node);
      if (detailAnchor !== null) {
        item.name = (detailAnchor.attributes.get('title') ?? '').trim();
        if (item.name.length === 0) {
          item.name = detailAnchor.text.trim();
        }
        const href = detailAnchor.attributes.get('href') ?? '';
        if (href.length > 0) {
          item.url = this.resolvePageUrl(href, runtime);
        }
      }
      if (item.name.length === 0) {
        item.name = this.find7sefunImageAlt(node);
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

      logger.info('7sefun search item[%{public}d]: name=%{public}s, url=%{public}s',
        i, item.name, item.url);
      if (item.name.length > 0 && item.url.length > 0) {
        items.push(item);
      }
    }

    const filtered = this.searchResultFilter.filterAndDeduplicate(items, runtime.rule.name);
    logger.info('Search rule 7sefun parsed by dedicated parser: nodes=%{public}d, valid=%{public}d',
      nodes.length, filtered.length);
    return filtered;
  }

  private find7sefunDetailAnchor(node: HtmlNode): HtmlNode | null {
    if (node.nodeType === NodeType.ELEMENT && node.tagName.toLowerCase() === 'a') {
      const href = node.attributes.get('href') ?? '';
      if (href.includes('/voddetail/')) {
        return node;
      }
    }
    for (let i = 0; i < node.childNodes.length; i++) {
      const found = this.find7sefunDetailAnchor(node.childNodes[i]);
      if (found !== null) {
        return found;
      }
    }
    return null;
  }

  private find7sefunImageAlt(node: HtmlNode): string {
    if (node.nodeType === NodeType.ELEMENT && node.tagName.toLowerCase() === 'img') {
      return (node.attributes.get('alt') ?? '').trim();
    }
    for (let i = 0; i < node.childNodes.length; i++) {
      const value = this.find7sefunImageAlt(node.childNodes[i]);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private selectFallbackSearchNodes(doc: HtmlDocument): HtmlNode[] {
    const containerCandidates: string[] = [
      "//div[contains(@class,'module-card-item') and contains(@class,'module-item')]",
      "//div[contains(@class,'cata_video_item')]",
      "//div[contains(@class,'public-list-box') and contains(@class,'search-box')]",
      "//div[contains(@class,'module-card-item')]",
      "//li[contains(@class,'video-item')]",
      "//li[contains(@class,'search-item')]"
    ];
    for (let i = 0; i < containerCandidates.length; i++) {
      const nodes = this.parser.selectNodes(containerCandidates[i], doc);
      if (nodes.length > 0) {
        return nodes;
      }
    }
    const detailLinkCandidates: string[] = [
      "//a[contains(@href,'/voddetail/')]",
      "//a[contains(@href,'/vod/detail/')]",
      "//a[contains(@href,'/detail/')]"
    ];
    for (let i = 0; i < detailLinkCandidates.length; i++) {
      const nodes = this.parser.selectNodes(detailLinkCandidates[i], doc);
      if (nodes.length > 0) {
        return nodes;
      }
    }
    return [];
  }

  private appendSearchItems(
    items: AnimeItem[],
    listNodes: HtmlNode[],
    runtime: RuleRuntimeModel,
    logPrefix: string
  ): void {
    for (let i = 0; i < listNodes.length; i++) {
      try {
        const item = this.parseSearchItem(listNodes[i], runtime);

        logger.info('%{public}s[%{public}d]: name=%{public}s, coverLen=%{public}d, coverPrefix=%{public}s',
          logPrefix, i, item.name, item.cover.length,
          item.cover.length > 80 ? item.cover.substring(0, 80) : item.cover);

        if (item.name.length > 0 || item.url.length > 0) {
          items.push(item);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warn('Failed to parse search item %{public}d: %{public}s', i, msg);
      }
    }
  }

  private parseSearchItem(node: HtmlNode, runtime: RuleRuntimeModel): AnimeItem {
    const item = new AnimeItem();
    item.sourceName = runtime.rule.name;
    item.sourceId = runtime.rule.id;

    item.name = this.selectFirstText(runtime.rule.searchName, node);
    if (item.name.length === 0 || this.isLikelyMetadataText(item.name)) {
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

    return item;
  }

  private selectFallbackName(context: HtmlDocument | HtmlNode): string {
    const candidates: string[] = [
      "./@title",
      ".//a/@title",
      ".//div[contains(@class,'module-card-item-title')]//strong/text()",
      ".//div[contains(@class,'module-card-item-title')]//a",
      ".//h5[contains(@class,'card-title')]/a/text()",
      ".//img/@alt",
      ".//div[contains(@class,'thumb-txt')]/text()",
      ".//a[contains(@class,'time-title')]/text()",
      "./text()",
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
    const detailCandidates: string[] = [
      ".//a[contains(@href,'/voddetail/')]/@href",
      ".//a[contains(@href,'/vod/detail/')]/@href",
      ".//a[contains(@href,'/detail/')]/@href",
      ".//h5[contains(@class,'card-title')]/a/@href",
      "./@href"
    ];
    for (let i = 0; i < detailCandidates.length; i++) {
      const value = this.selectFirstLink(detailCandidates[i], context);
      if (value.length > 0 && this.isLikelyDetailUrl(value)) {
        return value;
      }
    }
    const anyLinkCandidates: string[] = [
      ".//a[contains(@class,'public-list-exp')]/@href"
    ];
    for (let i = 0; i < anyLinkCandidates.length; i++) {
      const value = this.selectFirstLink(anyLinkCandidates[i], context);
      if (value.length > 0 && this.isLikelyDetailUrl(value)) {
        return value;
      }
    }
    return '';
  }

  private isLikelyDetailUrl(url: string): boolean {
    const trimmed = url.trim();
    if (trimmed.includes('/voddetail/')) {
      return true;
    }
    if (trimmed.includes('/vod/detail/')) {
      return true;
    }
    if (trimmed.includes('/detail/')) {
      return true;
    }
    if (trimmed.startsWith('javascript:')) {
      return false;
    }
    if (trimmed.startsWith('#')) {
      return false;
    }
    if (trimmed.includes('/vodplay/')) {
      return false;
    }
    return true;
  }

  private isLikelyMetadataText(text: string): boolean {
    const value = text.trim();
    if (value.length === 0) {
      return false;
    }
    if (value.includes('/') && (value.includes('日本') || value.includes('动漫') || value.includes('动画'))) {
      return true;
    }
    const commaCount = value.split(',').length - 1 + value.split('，').length - 1;
    if (commaCount >= 4 && !value.includes('《')) {
      return true;
    }
    return false;
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
      const value = result.strings[0].trim();
      if (this.looksLikeUrlOrPath(value)) {
        return value;
      }
      return '';
    }
    if (result.nodes.length > 0) {
      for (let i = 0; i < result.nodes.length; i++) {
        const directLink = this.extractNodeLink(result.nodes[i]);
        if (directLink.length > 0) {
          return directLink;
        }
      }
      for (let i = 0; i < result.nodes.length; i++) {
        const descendantLink = this.findDescendantLink(result.nodes[i]);
        if (descendantLink.length > 0) {
          return descendantLink;
        }
      }
      return '';
    }
    return '';
  }

  private extractNodeLink(node: HtmlNode): string {
    const attrs: string[] = ['href', 'data-href', 'data-url'];
    for (let i = 0; i < attrs.length; i++) {
      const value = node.attributes.get(attrs[i]) ?? '';
      const trimmed = value.trim();
      if (this.looksLikeUrlOrPath(trimmed)) {
        return trimmed;
      }
    }
    return '';
  }

  private findDescendantLink(node: HtmlNode): string {
    for (let i = 0; i < node.childNodes.length; i++) {
      const child = node.childNodes[i];
      if (child.nodeType !== NodeType.ELEMENT) {
        continue;
      }
      const directLink = this.extractNodeLink(child);
      if (directLink.length > 0) {
        return directLink;
      }
      const descendantLink = this.findDescendantLink(child);
      if (descendantLink.length > 0) {
        return descendantLink;
      }
    }
    return '';
  }

  private looksLikeUrlOrPath(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return true;
    }
    if (value.startsWith('//')) {
      return true;
    }
    if (value.startsWith('/') && value.length > 1) {
      return true;
    }
    if (value.startsWith('javascript:')) {
      return false;
    }
    if (value.startsWith('#')) {
      return false;
    }
    return false;
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
          const fallbackRoads = this.parseVodPlayRoads(html, runtime);
          if (fallbackRoads.length > 0) {
            logger.info('Using vodplay regex road parser for rule %{public}s, roads=%{public}d',
              runtime.rule.name, fallbackRoads.length);
            return fallbackRoads;
          }
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
          let episodeNodes = this.parser.selectNodes(runtime.rule.chapterResult, roadNode);
          if (episodeNodes.length === 0) {
            episodeNodes = this.selectFallbackEpisodeNodes(roadNode);
          }
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

  private parseVodPlayRoads(html: string, runtime: RuleRuntimeModel): PlaybackRoad[] {
    const roads: PlaybackRoad[] = [];
    const parts = html.split('vod-play-list-container');
    if (parts.length > 1) {
      for (let i = 1; i < parts.length; i++) {
        const road = this.parseVodPlayRoadPart(parts[i], runtime, roads.length);
        if (road !== null) {
          roads.push(road);
        }
      }
      return roads;
    }

    return this.parseVodPlayRoadsByUrlGroup(html, runtime);
  }

  private parseVodPlayRoadPart(part: string, runtime: RuleRuntimeModel, roadIndex: number): PlaybackRoad | null {
    const episodeNames: string[] = [];
    const episodeUrls: string[] = [];
    const seen = new Set<string>();
    const linkPattern: RegExp = /<a\b([^>]*)href=["']([^"']*(?:\/vodplay\/|\/vod\/play\/)[^"']*)["']([^>]*)>([\s\S]*?)<\/a>/g;
    let match = linkPattern.exec(part);
    while (match !== null) {
      const rawUrl = match[2].trim();
      if (!seen.has(rawUrl)) {
        seen.add(rawUrl);
        const attrText = match[1] + ' ' + match[3];
        let episodeName = this.extractVodPlayEpisodeName(rawUrl);
        if (episodeName.length === 0) {
          episodeName = this.extractEpisodeNameFromText(this.cleanHtmlSnippet(match[4]));
        }
        if (episodeName.length === 0) {
          episodeName = this.extractEpisodeNameFromText(this.extractTitleAttribute(attrText));
        }
        if (episodeName.length === 0) {
          episodeName = `第${episodeNames.length + 1}集`;
        }
        episodeNames.push(episodeName);
        episodeUrls.push(this.resolvePageUrl(rawUrl, runtime));
      }
      match = linkPattern.exec(part);
    }

    if (episodeUrls.length === 0) {
      return null;
    }
    const road = PlaybackRoad.create(`线路${roadIndex + 1}`, episodeNames, episodeUrls,
      runtime.rule.id, runtime.rule.name, '');
    logger.info('Vodplay fallback road %{public}d: episodes=%{public}d',
      roadIndex, episodeUrls.length);
    return road;
  }

  private parseVodPlayRoadsByUrlGroup(html: string, runtime: RuleRuntimeModel): PlaybackRoad[] {
    const roads: PlaybackRoad[] = [];
    const namesByRoad = new Map<string, string[]>();
    const urlsByRoad = new Map<string, string[]>();
    const seen = new Set<string>();
    const roadKeys: string[] = [];
    const linkPattern: RegExp = /<a\b([^>]*)href=["']([^"']*(?:\/vodplay\/|\/vod\/play\/)[^"']*)["']([^>]*)>([\s\S]*?)<\/a>/g;
    let match = linkPattern.exec(html);
    while (match !== null) {
      const rawUrl = match[2].trim();
      if (!seen.has(rawUrl)) {
        seen.add(rawUrl);
        const roadKey = this.extractVodPlayRoadKey(rawUrl);
        if (!namesByRoad.has(roadKey)) {
          namesByRoad.set(roadKey, []);
          urlsByRoad.set(roadKey, []);
          roadKeys.push(roadKey);
        }
        const attrText = match[1] + ' ' + match[3];
        let episodeName = this.extractVodPlayEpisodeName(rawUrl);
        if (episodeName.length === 0) {
          episodeName = this.extractEpisodeNameFromText(this.cleanHtmlSnippet(match[4]));
        }
        if (episodeName.length === 0) {
          episodeName = this.extractEpisodeNameFromText(this.extractTitleAttribute(attrText));
        }
        if (episodeName.length === 0) {
          const names = namesByRoad.get(roadKey) ?? [];
          episodeName = `第${names.length + 1}集`;
        }
        const names = namesByRoad.get(roadKey);
        const urls = urlsByRoad.get(roadKey);
        if (names !== undefined && urls !== undefined) {
          names.push(episodeName);
          urls.push(this.resolvePageUrl(rawUrl, runtime));
        }
      }
      match = linkPattern.exec(html);
    }

    for (let i = 0; i < roadKeys.length; i++) {
      const key = roadKeys[i];
      const episodeNames: string[] = [];
      const episodeUrls: string[] = [];
      const groupedNames = namesByRoad.get(key) ?? [];
      const groupedUrls = urlsByRoad.get(key) ?? [];
      for (let j = 0; j < groupedUrls.length; j++) {
        episodeNames.push(j < groupedNames.length ? groupedNames[j] : `第${j + 1}集`);
        episodeUrls.push(groupedUrls[j]);
      }
      if (episodeUrls.length > 0) {
        const road = PlaybackRoad.create(`线路${key}`, episodeNames, episodeUrls,
          runtime.rule.id, runtime.rule.name, '');
        roads.push(road);
        logger.info('Vodplay fallback road %{public}d: episodes=%{public}d',
          roads.length - 1, episodeUrls.length);
      }
    }
    return roads;
  }

  private extractVodPlayRoadKey(url: string): string {
    const oldStyle = url.match(/\/vodplay\/[^\/]*-(\d+)-\d+\.html/);
    if (oldStyle !== null) {
      return oldStyle[1];
    }
    const newStyle = url.match(/\/sid\/(\d+)\/nid\/\d+\.html/);
    if (newStyle !== null) {
      return newStyle[1];
    }
    return '1';
  }

  private extractVodPlayEpisodeName(url: string): string {
    let episodeText = '';
    const oldStyle = url.match(/\/vodplay\/[^\/]*-\d+-(\d+)\.html/);
    if (oldStyle !== null) {
      episodeText = oldStyle[1];
    }
    const newStyle = url.match(/\/sid\/\d+\/nid\/(\d+)\.html/);
    if (episodeText.length === 0 && newStyle !== null) {
      episodeText = newStyle[1];
    }
    if (episodeText.length === 0) {
      return '';
    }
    const episodeNo = parseInt(episodeText);
    if (!Number.isFinite(episodeNo) || episodeNo <= 0) {
      return '';
    }
    const text = episodeNo < 10 ? `0${episodeNo}` : `${episodeNo}`;
    return `第${text}集`;
  }

  private extractEpisodeNameFromText(value: string): string {
    const match = value.match(/第\s*([0-9０-９]+)\s*集/);
    if (match === null) {
      return '';
    }
    const normalized = this.normalizeDigits(match[1]);
    const episodeNo = parseInt(normalized);
    if (!Number.isFinite(episodeNo) || episodeNo <= 0) {
      return `第${match[1]}集`;
    }
    const text = episodeNo < 10 ? `0${episodeNo}` : `${episodeNo}`;
    return `第${text}集`;
  }

  private normalizeDigits(value: string): string {
    let result = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      const code = ch.charCodeAt(0);
      if (code >= 0xFF10 && code <= 0xFF19) {
        result += String.fromCharCode(code - 0xFF10 + 0x30);
      } else {
        result += ch;
      }
    }
    return result;
  }

  private extractTitleAttribute(attrs: string): string {
    const match = attrs.match(/\btitle=["']([^"']*)["']/);
    if (match === null) {
      return '';
    }
    return this.decodeHtmlEntities(match[1].trim());
  }

  private cleanHtmlSnippet(html: string): string {
    const withoutTags = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
    return this.decodeHtmlEntities(withoutTags);
  }

  private decodeHtmlEntities(value: string): string {
    return value
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .trim();
  }

  private selectFallbackRoadNodes(doc: HtmlDocument): HtmlNode[] {
    const roadCandidates: string[] = [
      "//div[contains(@class,'module-play-list-content')]",
      "//div[contains(@class,'module-play-list')]",
      "//div[contains(@class,'module-list') and contains(@class,'sort-list')]",
      "//div[contains(@class,'tab-pane')]",
      "//div[contains(@class,'vod-play-list-container')]",
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
      const links = this.parser.selectNodes(".//a[contains(@href,'/play/') or contains(@href,'/vodplay/')]", nodes[i]);
      if (links.length > 0) {
        result.push(nodes[i]);
      }
    }
    return result;
  }

  private selectFallbackEpisodeNodes(node: HtmlNode): HtmlNode[] {
    return this.parser.selectNodes(".//a[contains(@href,'/play/') or contains(@href,'/vodplay/')]", node);
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
