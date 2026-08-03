import { SettingsPage } from './SettingsPage'

@Entry
@Component
struct AppearanceSettingsPage {
  build() {
    Column() {
      SettingsPage({ standaloneDestination: 'settings_app' })
    }
    .width('100%')
    .height('100%')
  }
}
