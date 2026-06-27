export class UserSettings {
  defaultPlayerEngine: string = 'mpv';
  allowHttpRequests: boolean = false;
  snifferTimeoutMs: number = 15000;
  defaultSpeed: number = 1.0;
  defaultVolume: number = 1.0;
  autoPlay: boolean = true;
  autoRecordHistory: boolean = true;
  maxSearchHistory: number = 50;

  static fromJSON(json: Record<string, Object>): UserSettings {
    const settings = new UserSettings();
    if (json['defaultPlayerEngine'] !== undefined) settings.defaultPlayerEngine = json['defaultPlayerEngine'] as string;
    if (json['allowHttpRequests'] !== undefined) settings.allowHttpRequests = json['allowHttpRequests'] as boolean;
    if (json['snifferTimeoutMs'] !== undefined) settings.snifferTimeoutMs = json['snifferTimeoutMs'] as number;
    if (json['defaultSpeed'] !== undefined) settings.defaultSpeed = json['defaultSpeed'] as number;
    if (json['defaultVolume'] !== undefined) settings.defaultVolume = json['defaultVolume'] as number;
    if (json['autoPlay'] !== undefined) settings.autoPlay = json['autoPlay'] as boolean;
    if (json['autoRecordHistory'] !== undefined) settings.autoRecordHistory = json['autoRecordHistory'] as boolean;
    if (json['maxSearchHistory'] !== undefined) settings.maxSearchHistory = json['maxSearchHistory'] as number;
    return settings;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['defaultPlayerEngine'] = this.defaultPlayerEngine;
    result['allowHttpRequests'] = this.allowHttpRequests;
    result['snifferTimeoutMs'] = this.snifferTimeoutMs;
    result['defaultSpeed'] = this.defaultSpeed;
    result['defaultVolume'] = this.defaultVolume;
    result['autoPlay'] = this.autoPlay;
    result['autoRecordHistory'] = this.autoRecordHistory;
    result['maxSearchHistory'] = this.maxSearchHistory;
    return result;
  }
}
