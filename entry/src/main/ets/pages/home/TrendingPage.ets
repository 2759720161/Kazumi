import { RecommendSectionPage } from '../../components/recommend/RecommendSectionPage'
import { RecommendSectionType } from '../../utils/RecommendSectionCache'

@Entry
@Component
struct TrendingPage {
  build() {
    Stack() {
      RecommendSectionPage({
        sectionType: RecommendSectionType.TRENDING,
        title: '热门番组',
        showRank: false
      })
    }
    .width('100%')
    .height('100%')
  }
}
