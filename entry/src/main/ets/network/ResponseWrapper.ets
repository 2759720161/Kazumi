export class ResponseWrapper {
  statusCode: number = 0;
  headers: Record<string, string> = {};
  body: string = '';
  elapsedMs: number = 0;
  fromCache: boolean = false;

  get isSuccessful(): boolean {
    return this.statusCode >= 200 && this.statusCode < 300;
  }

  get isRedirect(): boolean {
    return this.statusCode >= 300 && this.statusCode < 400;
  }

  get isClientError(): boolean {
    return this.statusCode >= 400 && this.statusCode < 500;
  }

  get isServerError(): boolean {
    return this.statusCode >= 500;
  }
}