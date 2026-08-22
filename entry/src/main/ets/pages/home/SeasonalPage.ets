import { RecommendSectionPage } from '../../components/recommend/RecommendSectionPage'
import { RecommendSectionType } from '../../utils/RecommendSectionCache'

@Entry
@Component
struct SeasonalPage {
  build() {
    Stack() {
      RecommendSectionPage({
        sectionType: RecommendSectionType.SEASONAL,
        title: '季度新番',
        showRank: false
      })
    }
    .width('100%')
    .height('100%')
  }
}
