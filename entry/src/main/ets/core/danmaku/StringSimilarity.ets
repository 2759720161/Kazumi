export class StringSimilarity {
  static normalize(text: string): string {
    if (text.length === 0) {
      return ''
    }
    let result = ''
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i)
      if ((code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A) ||
          (code >= 0x30 && code <= 0x39) ||
          (code >= 0x4E00 && code <= 0x9FFF) ||
          (code >= 0x3040 && code <= 0x309F) ||
          (code >= 0x30A0 && code <= 0x30FF)) {
        result += text.charAt(i)
      }
    }
    result = result.toLowerCase()
    return result
  }

  static levenshteinDistance(s1: string, s2: string): number {
    if (s1 === s2) {
      return 0
    }
    if (s1.length === 0) {
      return s2.length
    }
    if (s2.length === 0) {
      return s1.length
    }

    const shorter = s1.length <= s2.length ? s1 : s2
    const longer = s1.length > s2.length ? s1 : s2

    let v0: number[] = []
    let v1: number[] = []
    for (let i = 0; i <= shorter.length; i++) {
      v0.push(i)
      v1.push(0)
    }

    for (let i = 0; i < longer.length; i++) {
      v1[0] = i + 1

      for (let j = 0; j < shorter.length; j++) {
        const cost = (longer.charAt(i) === shorter.charAt(j)) ? 0 : 1
        const minVal = Math.min(v1[j] + 1, Math.min(v0[j + 1] + 1, v0[j] + cost))
        v1[j + 1] = minVal
      }

      const temp = v0
      v0 = v1
      v1 = temp
    }

    return v0[shorter.length]
  }

  static calculateSimilarity(s1: string, s2: string): number {
    const maxLength = Math.max(s1.length, s2.length)
    if (maxLength === 0) {
      return 1.0
    }
    if (s1 === s2) {
      return 1.0
    }
    const distance = StringSimilarity.levenshteinDistance(s1, s2)
    return 1.0 - distance / maxLength
  }

  static calculateNormalizedSimilarity(titleA: string, titleB: string): number {
    const normalizedA = StringSimilarity.normalize(titleA)
    const normalizedB = StringSimilarity.normalize(titleB)
    return StringSimilarity.calculateSimilarity(normalizedA, normalizedB)
  }
}