import { AntiCrawlerConfig } from '../../models/RuleSource';
import { Logger } from '../../utils/Logger';

const logger = new Logger('AntiCrawlHandler');

export interface AntiCrawlResult {
  success: boolean;
  cookies: Record<string, string>;
  message: string;
}

export class AntiCrawlHandler {
  async handleAntiCrawl(config: AntiCrawlerConfig, url: string): Promise<AntiCrawlResult> {
    if (!config.enabled) {
      return { success: true, cookies: {}, message: 'No anti-crawl needed' };
    }

    logger.info('Anti-crawl detected for %{public}s, type=%{public}d', url, config.captchaType);

    if (config.captchaScript.length > 0) {
      logger.info('Custom captcha script available - requires WebView handling');
      return {
        success: false,
        cookies: {},
        message: 'Captcha requires WebView interaction - not yet implemented in this handler'
      };
    }

    if (config.captchaType > 0) {
      logger.info('Captcha type %{public}d detected - requires user interaction', config.captchaType);
      return {
        success: false,
        cookies: {},
        message: `Captcha type ${config.captchaType} requires WebView interaction`
      };
    }

    return { success: true, cookies: {}, message: 'Anti-crawl handled' };
  }

  isCaptchaResponse(html: string): boolean {
    const lower = html.toLowerCase();
    const normalPageMarkers: string[] = [
      'id="search_results_wrapper"',
      'cata_video_item',
      'public-list-box search-box',
      'module-card-item',
      'vod-detail'
    ];
    for (let i = 0; i < normalPageMarkers.length; i++) {
      if (lower.includes(normalPageMarkers[i])) {
        return false;
      }
    }

    const captchaIndicators: string[] = [
      'captcha',
      'verify',
      'challenge',
      'cf-browser-verification',
      '系统提示',
      '安全验证',
      '访问验证',
      '人机验证',
      '\u9A8C\u8BC1\u7801'
    ];
    for (let i = 0; i < captchaIndicators.length; i++) {
      if (lower.includes(captchaIndicators[i])) {
        return true;
      }
    }
    return false;
  }

  isBlockedResponse(statusCode: number): boolean {
    return statusCode === 403 || statusCode === 429;
  }
}
