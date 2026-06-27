import { Logger } from '../../utils/Logger'

const logger = new Logger('AnimeSeason')

const SEASON_NAMES: string[] = ['冬季', '春季', '夏季', '秋季']
const SEASON_SHORT_NAMES: string[] = ['冬', '春', '夏', '秋']
const WEEKDAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
const WEEKDAY_FULL_NAMES: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']
const SEASON_QUARTER_ORDER: number[] = [3, 2, 1, 0]
const YEAR_RANGE_COUNT: number = 20

export class QuarterItem {
  quarterIndex: number = 0
  seasonName: string = ''
  isSelected: boolean = false
}

export class YearQuarterItem {
  year: number = 0
  quarters: QuarterItem[] = []
  isHighlighted: boolean = false
}

export class AnimeSeason {
  static getSeasonString(date?: Date): string {
    const d = date ?? new Date()
    const year = d.getFullYear()
    const quarter = AnimeSeason.getSeasonQuarter(d)
    return `${year}年${SEASON_NAMES[quarter]}新番`
  }

  static getSeasonShortString(year: number, quarter: number): string {
    if (quarter < 0 || quarter > 3) {
      return '--'
    }
    return `${year}${SEASON_SHORT_NAMES[quarter]}`
  }

  static getCurrentWeekdayIndex(): number {
    const day = new Date().getDay()
    if (day === 0) return 6
    return day - 1
  }

  static getWeekdayName(weekdayIndex: number): string {
    if (weekdayIndex < 0 || weekdayIndex > 6) {
      return '--'
    }
    return WEEKDAY_NAMES[weekdayIndex]
  }

  static getWeekdayFullName(weekdayIndex: number): string {
    if (weekdayIndex < 0 || weekdayIndex > 6) {
      return '--'
    }
    return WEEKDAY_FULL_NAMES[weekdayIndex]
  }

  static getSeasonQuarter(date?: Date): number {
    const d = date ?? new Date()
    const month = d.getMonth()
    return Math.floor(month / 3)
  }

  static isCurrentSeason(year: number, quarter: number): boolean {
    const now = new Date()
    return year === now.getFullYear() && quarter === Math.floor(now.getMonth() / 3)
  }

  static getSeasonDateRange(year: number, quarter: number): string[] {
    const startMonth = quarter * 3
    const startDate = new Date(year, startMonth, 1)
    const endDate = new Date(year, startMonth + 3, 1)
    return [AnimeSeason.formatDate(startDate), AnimeSeason.formatDate(endDate)]
  }

  static generateYearQuarterList(selectedYear: number, selectedQuarter: number): YearQuarterItem[] {
    const result: YearQuarterItem[] = []
    const now = new Date()
    const currentYear = now.getFullYear()

    if (currentYear < 2000 || currentYear > 2100) {
      return result
    }

    for (let y = 0; y < YEAR_RANGE_COUNT; y++) {
      const year = currentYear - y
      const quarters: QuarterItem[] = []

      for (let q = 0; q < SEASON_QUARTER_ORDER.length; q++) {
        const quarterIndex = SEASON_QUARTER_ORDER[q]
        const startMonth = quarterIndex * 3
        const quarterStartDate = new Date(year, startMonth, 1)

        if (now.getTime() < quarterStartDate.getTime()) {
          continue
        }

        const item = new QuarterItem()
        item.quarterIndex = quarterIndex
        item.seasonName = SEASON_SHORT_NAMES[quarterIndex]
        item.isSelected = (year === selectedYear && quarterIndex === selectedQuarter)
        quarters.push(item)
      }

      if (quarters.length === 0) {
        continue
      }

      const yearItem = new YearQuarterItem()
      yearItem.year = year
      yearItem.quarters = quarters
      yearItem.isHighlighted = (year === selectedYear)
      result.push(yearItem)
    }

    return result
  }

  static getSeasonStartAndEnd(date?: Date): string[] {
    const d = date ?? new Date()
    const year = d.getFullYear()
    const quarter = AnimeSeason.getSeasonQuarter(d)
    const startMonth = quarter * 3
    const startDate = new Date(year, startMonth, 1)
    const endDate = new Date(year, startMonth + 3, 1)
    return [AnimeSeason.formatDate(startDate), AnimeSeason.formatDate(endDate)]
  }

  private static formatDate(d: Date): string {
    const y = d.getFullYear()
    const m = (d.getMonth() + 1).toString().padStart(2, '0')
    const day = d.getDate().toString().padStart(2, '0')
    return `${y}-${m}-${day}`
  }
}