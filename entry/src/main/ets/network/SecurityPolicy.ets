import { PreferencesStore } from '../store/PreferencesStore';
import { Logger } from '../utils/Logger';

const logger = new Logger('SecurityPolicy');

export class SecurityPolicy {
  private static instance: SecurityPolicy | null = null;
  private allowHttpRequests: boolean = false;
  private httpWarningShown: Set<string> = new Set();

  private constructor() {}

  static getInstance(): SecurityPolicy {
    if (SecurityPolicy.instance === null) {
      SecurityPolicy.instance = new SecurityPolicy();
    }
    return SecurityPolicy.instance;
  }

  async init(): Promise<void> {
    const prefs = PreferencesStore.getInstance();
    this.allowHttpRequests = await prefs.getBoolean('allow_http_requests', false);
    logger.info('SecurityPolicy initialized, allowHttpRequests=%{public}s',
      String(this.allowHttpRequests));
  }

  checkUrl(url: string): boolean {
    if (url.startsWith('https://')) {
      return true;
    }
    if (url.startsWith('http://')) {
      if (this.allowHttpRequests) {
        logger.info('HTTP request allowed: %{public}s', url);
        return true;
      }
      logger.warn('HTTP request blocked by security policy: %{public}s', url);
      return false;
    }
    return true;
  }

  isHttpUrl(url: string): boolean {
    return url.startsWith('http://');
  }

  hasShownHttpWarning(ruleName: string): boolean {
    return this.httpWarningShown.has(ruleName);
  }

  markHttpWarningShown(ruleName: string): void {
    this.httpWarningShown.add(ruleName);
  }

  async setAllowHttpRequests(allow: boolean): Promise<void> {
    this.allowHttpRequests = allow;
    const prefs = PreferencesStore.getInstance();
    await prefs.setBoolean('allow_http_requests', allow);
    logger.info('allowHttpRequests set to %{public}s', String(allow));
  }

  getAllowHttpRequests(): boolean {
    return this.allowHttpRequests;
  }
}