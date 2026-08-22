import { RecommendSectionPage } from '../../components/recommend/RecommendSectionPage'
import { RecommendSectionType } from '../../utils/RecommendSectionCache'

@Entry
@Component
struct HighScorePage {
  build() {
    Stack() {
      RecommendSectionPage({
        sectionType: RecommendSectionType.HIGH_SCORE,
        title: '高分佳作',
        showRank: true
      })
    }
    .width('100%')
    .height('100%')
  }
}
