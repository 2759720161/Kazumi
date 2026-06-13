export class RequestConfig {
  url: string = '';
  method: string = 'GET';
  headers: Record<string, string> = {};
  body: string = '';
  timeout: number = 10000;
  followRedirects: boolean = true;
  retryPolicy: RetryPolicy | null = null;
  proxy: ProxyConfig | null = null;

  static createGet(url: string, headers?: Record<string, string>): RequestConfig {
    const config = new RequestConfig();
    config.url = url;
    config.method = 'GET';
    if (headers !== undefined) {
      config.headers = headers;
    }
    return config;
  }

  static createPost(url: string, body: string, headers?: Record<string, string>): RequestConfig {
    const config = new RequestConfig();
    config.url = url;
    config.method = 'POST';
    config.body = body;
    if (headers !== undefined) {
      config.headers = headers;
    }
    return config;
  }
}

export class ProxyConfig {
  host: string = '';
  port: number = 0;
  username: string = '';
  password: string = '';

  constructor(host: string, port: number, username?: string, password?: string) {
    this.host = host;
    this.port = port;
    if (username !== undefined) {
      this.username = username;
    }
    if (password !== undefined) {
      this.password = password;
    }
  }
}

export class RetryPolicy {
  maxRetries: number = 3;
  baseDelayMs: number = 1000;
  maxDelayMs: number = 10000;

  constructor(maxRetries?: number, baseDelayMs?: number) {
    if (maxRetries !== undefined) {
      this.maxRetries = maxRetries;
    }
    if (baseDelayMs !== undefined) {
      this.baseDelayMs = baseDelayMs;
    }
  }

  getDelayMs(retryCount: number): number {
    const delay = this.baseDelayMs * Math.pow(2, retryCount);
    return Math.min(delay, this.maxDelayMs);
  }
}