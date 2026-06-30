export class SniffRule {
  name: string = ''
  category: string = ''
  ruleType: string = ''
  patterns: string[] = []
  action: string = ''
  actionParams: Record<string, string> = {}
  priority: number = 0
  enabled: boolean = true
  sourceTag: string = ''
}

export class WeakCandidateVerdict {
  isWeak: boolean = false
  delayMs: number = 0
  matchedRuleName: string = ''
}

export class PromotePageVerdict {
  shouldPromote: boolean = false
  matchedRuleName: string = ''
}

export class FilterVerdict {
  shouldReject: boolean = false
  rejectReason: string = ''
  matchedRuleName: string = ''
}

export class ProtocolCapability {
  protocol: string = ''
  supported: boolean = false
  message: string = ''
}

export class ScoringModifier {
  ruleName: string = ''
  scoreDelta: number = 0
}
