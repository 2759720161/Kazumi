import { http } from '@kit.NetworkKit';
import { RequestConfig, RetryPolicy } from './RequestConfig';
import { ResponseWrapper } from './ResponseWrapper';
import { SecurityPolicy } from './SecurityPolicy';
import { CookieManager } from './CookieManager';
import { Logger, extractErrorMsg } from '../utils/Logger';

const logger = new Logger('HttpClient');

export class HttpHeaders {
  'User-Agent': string = '';
  Referer: string = '';
  Cookie: string = '';
  'Content-Type': string = '';
  Accept: string = '';
}

export class HttpClient {
  private securityPolicy: SecurityPolicy;
  private cookieManager: CookieManager;

  constructor() {
    this.securityPolicy = SecurityPolicy.getInstance();
    this.cookieManager = CookieManager.getInstance();
  }

  async request(config: RequestConfig): Promise<ResponseWrapper> {
    const securityResult = this.securityPolicy.checkUrl(config.url);
    if (!securityResult) {
      const wrapper = new ResponseWrapper();
      wrapper.statusCode = 403;
      wrapper.body = 'Request blocked by security policy';
      return wrapper;
    }

    const retryPolicy = config.retryPolicy !== null ? config.retryPolicy : new RetryPolicy();
    const connectionRetryPolicy = config.connectionRetryPolicy !== null
      ? config.connectionRetryPolicy : new RetryPolicy(0, 500);
    let lastErrorMsg: string = 'Unknown error';
    let lastStatusCode: number = 0;
    let nextRetryIsConnection = false;

    const maxAttempts = Math.max(retryPolicy.maxRetries, connectionRetryPolicy.maxRetries);
    for (let attempt = 0; attempt <= maxAttempts; attempt++) {
      if (attempt > 0) {
        const delay = nextRetryIsConnection
          ? connectionRetryPolicy.getDelayMs(attempt - 1)
          : retryPolicy.getDelayMs(attempt - 1);
        await this.sleep(delay);
        logger.info('Retry attempt %{public}d/%{public}d (%{public}s) after %{public}d ms',
          attempt, maxAttempts, nextRetryIsConnection ? 'connection' : 'http', delay);
      }

      let shouldRetry = false;
      try {
        const result = await this.executeRequest(config);
        if (result.isSuccessful || result.isRedirect) {
          return result;
        }
        if (result.isClientError && result.statusCode !== 429) {
          if (result.statusCode === 403) {
            logger.warn('HTTP 403鉴权失败，不重试')
          }
          return result;
        }
        lastStatusCode = result.statusCode;
        lastErrorMsg = `HTTP ${result.statusCode}`;
        if (attempt < retryPolicy.maxRetries) {
          nextRetryIsConnection = false;
          shouldRetry = true;
        }
      } catch (err) {
        lastErrorMsg = extractErrorMsg(err as Object);
        if (HttpClient.isConnectionFailureMsg(lastErrorMsg)
          && attempt < connectionRetryPolicy.maxRetries) {
          logger.warn('Transient connection failure, retrying host=%{public}s: %{public}s',
            HttpClient.extractHost(config.url), lastErrorMsg);
          nextRetryIsConnection = true;
          shouldRetry = true;
        } else if (HttpClient.isDnsFailureMsg(lastErrorMsg)) {
          const hostName = HttpClient.extractHost(config.url)
          logger.warn('DNS解析失败，不重试: host=%{public}s', hostName)
          const wrapper = new ResponseWrapper()
          wrapper.statusCode = 0
          wrapper.body = lastErrorMsg
          return wrapper
        } else if (attempt < retryPolicy.maxRetries) {
          nextRetryIsConnection = false;
          shouldRetry = true;
        } else {
          logger.warn('Request attempt %{public}d failed: %{public}s', attempt, lastErrorMsg);
        }
      }
      if (!shouldRetry) {
        break;
      }
    }

    const wrapper = new ResponseWrapper();
    wrapper.statusCode = lastStatusCode;
    wrapper.body = lastErrorMsg;
    return wrapper;
  }

  async get(url: string, headers?: Record<string, string>): Promise<ResponseWrapper> {
    const config = RequestConfig.createGet(url, headers);
    return await this.request(config);
  }

  async post(url: string, body: string, headers?: Record<string, string>): Promise<ResponseWrapper> {
    const config = RequestConfig.createPost(url, body, headers);
    return await this.request(config);
  }

  private async executeRequest(config: RequestConfig): Promise<ResponseWrapper> {
    const start = Date.now();
    const httpResponse = http.createHttp();

    try {
      const method = config.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET;

      const requestHeaders: Record<string, string> = {};
      if (config.headers) {
        const keys = Object.keys(config.headers);
        for (let i = 0; i < keys.length; i++) {
          requestHeaders[keys[i]] = config.headers[keys[i]];
        }
      }

      const cookieHeader = this.cookieManager.getCookieHeaderForUrl(config.url);
      if (cookieHeader.length > 0) {
        requestHeaders['Cookie'] = cookieHeader;
        logger.info('HTTP request cookie attached: host=%{public}s, length=%{public}d',
          HttpClient.extractHost(config.url), cookieHeader.length);
      }

      const requestOptions: http.HttpRequestOptions = {
        method: method,
        header: requestHeaders,
        readTimeout: config.timeout,
        connectTimeout: config.timeout,
        expectDataType: http.HttpDataType.STRING,
        extraData: config.method === 'POST' ? config.body : undefined
      };

      const result = await httpResponse.request(config.url, requestOptions);

      const wrapper = new ResponseWrapper();
      wrapper.statusCode = result.responseCode as number;
      const resultBody = result.result;
      if (typeof resultBody === 'string') {
        wrapper.body = resultBody;
      } else {
        wrapper.body = JSON.stringify(resultBody);
      }
      wrapper.elapsedMs = Date.now() - start;

      try {
        if (result.header) {
          const headerRecord = result.header as Record<string, Object>;
          const headerKeys = Object.keys(headerRecord);
          for (let h = 0; h < headerKeys.length; h++) {
            if (headerKeys[h].toLowerCase() === 'set-cookie') {
              const setCookieObj = headerRecord[headerKeys[h]];
              if (typeof setCookieObj === 'string') {
                this.cookieManager.extractCookiesFromSetCookieHeader(config.url, setCookieObj as string);
              } else if (setCookieObj instanceof Array) {
                const cookieArr = setCookieObj as string[];
                for (let s = 0; s < cookieArr.length; s++) {
                  const item = cookieArr[s];
                  if (typeof item === 'string') {
                    this.cookieManager.extractCookiesFromSetCookieHeader(config.url, item);
                  }
                }
              }
              break;
            }
          }
        }
      } catch (cookieErr) {
        logger.debug('Cookie parsing failed, ignoring: %{public}s',
          cookieErr instanceof Error ? cookieErr.message : String(cookieErr));
      }

      logger.debug('%{public}s %{public}s -> %{public}d (%{public}d ms)',
        config.method, config.url, wrapper.statusCode, wrapper.elapsedMs);

      return wrapper;
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      const wrapper = new ResponseWrapper();
      wrapper.statusCode = 0;
      wrapper.body = msg;
      wrapper.elapsedMs = Date.now() - start;
      throw new Error(msg);
    } finally {
      httpResponse.destroy();
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private static isDnsFailureMsg(msg: string): boolean {
    if (msg.length === 0) {
      return false
    }
    const lower = msg.toLowerCase()
    return lower.indexOf('failed to resolve') >= 0 || lower.indexOf('resolve the host') >= 0
  }

  private static isConnectionFailureMsg(msg: string): boolean {
    if (msg.length === 0) {
      return false
    }
    const lower = msg.toLowerCase()
    return lower.indexOf('failed to connect') >= 0
      || lower.indexOf('connection') >= 0
      || lower.indexOf('socket') >= 0
      || lower.indexOf('connection reset') >= 0
      || lower.indexOf('connection refused') >= 0
      || lower.indexOf('internal error') >= 0
  }

  private static extractHost(url: string): string {
    const schemeIndex = url.indexOf('://')
    if (schemeIndex < 0) {
      return url
    }
    let rest = url.substring(schemeIndex + 3)
    const slashIndex = rest.indexOf('/')
    if (slashIndex >= 0) {
      rest = rest.substring(0, slashIndex)
    }
    const colonIndex = rest.lastIndexOf(':')
    if (colonIndex >= 0) {
      rest = rest.substring(0, colonIndex)
    }
    return rest
  }
}
