import { SettingsPage } from './SettingsPage'

@Entry
@Component
struct PlayerSettingsPage {
  build() {
    Column() {
      SettingsPage({ standaloneDestination: 'settings_player' })
    }
    .width('100%')
    .height('100%')
  }
}
