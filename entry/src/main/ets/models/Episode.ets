export class Episode {
  name: string = '';
  url: string = '';
  index: number = 0;

  static fromJSON(json: Record<string, Object>): Episode {
    const ep = new Episode();
    if (json['name'] !== undefined) ep.name = json['name'] as string;
    if (json['url'] !== undefined) ep.url = json['url'] as string;
    if (json['index'] !== undefined) ep.index = json['index'] as number;
    return ep;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['name'] = this.name;
    result['url'] = this.url;
    result['index'] = this.index;
    return result;
  }
}