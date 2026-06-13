import { HttpClient } from '../../network/HttpClient'
import { RequestConfig, RetryPolicy } from '../../network/RequestConfig'
import { ResponseWrapper } from '../../network/ResponseWrapper'
import { DandanCredentialStore } from './DandanCredentialStore'
import { DandanSignatureUtil } from './DandanSignatureUtil'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DandanApiClient')

const OFFICIAL_API_BASE = 'https://api.dandanplay.net'
const PROXY_CANDIDATES: string[] = [
  'https://api.dandanplay.niltree.com',
  'https://api2.dandanplay.niltree.com',
]
const DANMAKU_API_TIMEOUT_MS = 15000
const DANMAKU_API_MAX_RETRIES = 1

const USER_AGENTS: string[] = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
]

export class DandanApiClient {
  private httpClient: HttpClient = new HttpClient()
  private credentialStore: DandanCredentialStore = DandanCredentialStore.getInstance()

  private static instance: DandanApiClient | null = null

  private constructor() {}

  static getInstance(): DandanApiClient {
    if (DandanApiClient.instance === null) {
      DandanApiClient.instance = new DandanApiClient()
    }
    return DandanApiClient.instance
  }

  async get(path: string, queryParameters?: Record<string, string>): Promise<ResponseWrapper> {
    const hasCredentials = this.credentialStore.hasCredentials()

    if (hasCredentials) {
      logger.info('弹幕API模式: official-signed, host=%{public}s', OFFICIAL_API_BASE)
      logger.info('官方凭据: 已配置')
      const result = await this.signedGet(path, queryParameters)
      if (result.statusCode === 403) {
        logger.warn('官方API签名鉴权失败(HTTP 403), 降级到反代候选列表')
        return await this.proxyGetWithCandidates(path, queryParameters)
      }
      return result
    }

    logger.info('弹幕API模式: proxy, host=%{public}s', PROXY_CANDIDATES.length > 0 ? PROXY_CANDIDATES[0] : 'none')
    logger.info('官方凭据: 未配置')
    return await this.proxyGetWithCandidates(path, queryParameters)
  }

  private async signedGet(path: string, queryParameters?: Record<string, string>): Promise<ResponseWrapper> {
    const appId = this.credentialStore.getAppId()
    const appSecret = this.credentialStore.getAppSecret()
    const timestamp = Math.floor(Date.now() / 1000)

    let signature = ''
    try {
      signature = await DandanSignatureUtil.generateSignature(appId, appSecret, timestamp, path)
    } catch (err) {
      logger.error('签名计算失败, 降级到反代候选列表: %{public}s',
        err instanceof Error ? err.message : String(err))
      return await this.proxyGetWithCandidates(path, queryParameters)
    }

    const url = this.buildUrl(OFFICIAL_API_BASE, path, queryParameters)
    const headers = this.buildSignedHeaders(appId, timestamp, signature)

    logger.info('签名请求: path=%{public}s', path)
    const config = RequestConfig.createGet(url, headers)
    config.timeout = DANMAKU_API_TIMEOUT_MS
    config.retryPolicy = new RetryPolicy(DANMAKU_API_MAX_RETRIES, 1000)

    return await this.httpClient.request(config)
  }

  private async proxyGetWithCandidates(path: string, queryParameters?: Record<string, string>): Promise<ResponseWrapper> {
    if (PROXY_CANDIDATES.length === 0) {
      logger.warn('反代候选列表为空')
      const wrapper = new ResponseWrapper()
      wrapper.statusCode = 0
      wrapper.body = 'No proxy candidates available'
      return wrapper
    }

    let allDnsFailure = true
    let lastResult: ResponseWrapper | null = null

    for (let i = 0; i < PROXY_CANDIDATES.length; i++) {
      const candidateBase = PROXY_CANDIDATES[i]
      logger.info('请求host: %{public}s', candidateBase)

      const url = this.buildUrl(candidateBase, path, queryParameters)
      const config = RequestConfig.createGet(url)
      config.timeout = DANMAKU_API_TIMEOUT_MS
      config.retryPolicy = new RetryPolicy(DANMAKU_API_MAX_RETRIES, 1000)

      try {
        const result = await this.httpClient.request(config)
        if (result.isSuccessful) {
          return result
        }
        if (DandanApiClient.isDnsFailure(result)) {
          logger.warn('反代候选失败: host=%{public}s, 原因=DNS解析失败', candidateBase)
        } else {
          allDnsFailure = false
          logger.warn('反代候选失败: host=%{public}s, 原因=HTTP %{public}d', candidateBase, result.statusCode)
        }
        lastResult = result
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        if (msg.toLowerCase().indexOf('resolve') >= 0) {
          logger.warn('反代候选失败: host=%{public}s, 原因=DNS解析失败', candidateBase)
        } else {
          allDnsFailure = false
          logger.warn('反代候选失败: host=%{public}s, 原因=%{public}s', candidateBase, msg)
        }
      }
    }

    if (allDnsFailure) {
      logger.error('弹幕源不可用：未配置官方凭据，反代域名解析失败')
    } else {
      logger.error('所有反代请求失败')
    }

    if (lastResult !== null) {
      return lastResult
    }
    const wrapper = new ResponseWrapper()
    wrapper.statusCode = 0
    wrapper.body = allDnsFailure ? 'DNS resolution failed for all proxy candidates' : 'All proxy requests failed'
    return wrapper
  }

  private static isDnsFailure(response: ResponseWrapper): boolean {
    if (response.statusCode !== 0) {
      return false
    }
    const body = response.body.toLowerCase()
    return body.indexOf('failed to resolve') >= 0 || body.indexOf('resolve the host') >= 0
  }

  private buildSignedHeaders(appId: string, timestamp: number, signature: string): Record<string, string> {
    const headers: Record<string, string> = {}
    headers['X-Auth'] = '1'
    headers['X-AppId'] = appId
    headers['X-Timestamp'] = String(timestamp)
    headers['X-Signature'] = signature
    headers['user-agent'] = this.getRandomUA()
    headers['referer'] = ''
    return headers
  }

  private buildUrl(base: string, path: string, queryParameters?: Record<string, string>): string {
    let url = `${base}${path}`
    if (queryParameters !== undefined) {
      const keys = Object.keys(queryParameters)
      if (keys.length > 0) {
        const parts: string[] = []
        for (let i = 0; i < keys.length; i++) {
          parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(queryParameters[keys[i]])}`)
        }
        url = `${url}?${parts.join('&')}`
      }
    }
    return url
  }

  private getRandomUA(): string {
    const index = Math.floor(Math.random() * USER_AGENTS.length)
    return USER_AGENTS[index]
  }
}
