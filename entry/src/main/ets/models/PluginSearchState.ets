export class PluginSearchState {
  pluginId: number = -1
  pluginName: string = ''
  status: string = 'pending'
  errorMessage: string = ''
  searchResults: SearchResultRef[] = []
  keyword: string = ''

  static pending(id: number, name: string): PluginSearchState {
    const state = new PluginSearchState()
    state.pluginId = id
    state.pluginName = name
    state.status = 'pending'
    return state
  }

  static success(id: number, name: string, results: SearchResultRef[]): PluginSearchState {
    const state = new PluginSearchState()
    state.pluginId = id
    state.pluginName = name
    state.status = 'success'
    state.searchResults = results
    return state
  }

  static noResult(id: number, name: string): PluginSearchState {
    const state = new PluginSearchState()
    state.pluginId = id
    state.pluginName = name
    state.status = 'noResult'
    return state
  }

  static captcha(id: number, name: string, message: string): PluginSearchState {
    const state = new PluginSearchState()
    state.pluginId = id
    state.pluginName = name
    state.status = 'captcha'
    state.errorMessage = message
    return state
  }

  static error(id: number, name: string, message: string): PluginSearchState {
    const state = new PluginSearchState()
    state.pluginId = id
    state.pluginName = name
    state.status = 'error'
    state.errorMessage = message
    return state
  }

  getStatusColor(): ResourceStr {
    if (this.status === 'success') return $r('app.color.status_success')
    if (this.status === 'noResult') return $r('app.color.status_warning')
    if (this.status === 'captcha') return $r('app.color.status_info')
    if (this.status === 'error') return $r('app.color.status_error')
    return $r('app.color.status_default')
  }
}

export class SearchResultRef {
  name: string = ''
  url: string = ''
  sourceId: number = -1
  sourceName: string = ''
}