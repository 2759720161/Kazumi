export class JSInjector {
  private static SCRIPT_HASH: string = 'BUILTIN_SNIFFER_V3'

  static getSnifferScript(useLegacyParser: boolean): string {
    if (useLegacyParser) {
      return JSInjector.getLegacySnifferScript()
    }
    return JSInjector.getModernSnifferScript()
  }

  static getLegacySnifferScript(): string {
    return `
(function() {
  if (window.__kazumi_sniffer_injected) return;
  window.__kazumi_sniffer_injected = true;
  window.__kazumi_sniffed_results = [];

  function postResult(url, type, source) {
    window.__kazumi_sniffed_results.push({url: url, type: type, source: source, ts: Date.now()});
    console.log('[KazumiSniffer] postResult: ' + type + ' ' + source + ' ' + url.substring(0, 80));
    if (window.JSBridgeDebug && window.JSBridgeDebug.postMessage) {
      window.JSBridgeDebug.postMessage(JSON.stringify({url: url, type: type, source: source}));
    } else if (window.jsBridge && window.jsBridge.postMessage) {
      window.jsBridge.postMessage(JSON.stringify({url: url, type: type, source: source}));
    }
  }

  function isVideoUrl(url) {
    if (!url) return false;
    var lower = url.toLowerCase();
    if (lower.indexOf('.m3u8') !== -1 || lower.indexOf('.mp4') !== -1 ||
        lower.indexOf('.flv') !== -1 || lower.indexOf('.mknvideo') !== -1 ||
        lower.indexOf('m3u8') !== -1) {
      return true;
    }
    return isLikelyExtensionlessMediaUrl(lower);
  }

  function isLikelyExtensionlessMediaUrl(lower) {
    if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) return false;
    var nonMediaDomains = ['byteimg.com', 'pstatp.com', 'douyinpic.com', 'snssdk.com'];
    for (var d = 0; d < nonMediaDomains.length; d++) {
      if (lower.indexOf(nonMediaDomains[d]) !== -1) return false;
    }
    var clean = lower.split('?')[0].split('#')[0];
    var nonMedia = ['.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json'];
    for (var i = 0; i < nonMedia.length; i++) {
      if (clean.lastIndexOf(nonMedia[i]) === clean.length - nonMedia[i].length) return false;
    }
    var hints = ['://v16', '://v26', '://v3', '://v6', '://v9', '://lf', '://lf2', '://lf3', '://lf6', '://lf9', '://lf20', '://vkc', '://vkce', '://fev', '://febo', '/video/tos/', 'videocdn', 'video-cdn', 'mcdn', 'bytecdntp', 'bytetos.com', 'csp-sign', 'tos-cn-v-', 'play.mknacg.top:9009/d/', 'tjdownload.pan.wo.cn', 'pan.wo.cn/openapi/download', '/openapi/download?fid=', '/videos/', '/videoplayback', '/videoplay', 'cdnvideo', 'cdn-video', 'hlsvideo', 'streaming', 'liveld'];
    for (var j = 0; j < hints.length; j++) {
      if (lower.indexOf(hints[j]) !== -1) return true;
    }
    return false;
  }

  var iframes = document.querySelectorAll('iframe');
  for (var i = 0; i < iframes.length; i++) {
    var iframeSrc = iframes[i].src || iframes[i].getAttribute('src');
    if (iframeSrc && isVideoUrl(iframeSrc)) {
      postResult(iframeSrc, 'iframe', 'iframe_scan');
    }
  }

  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeName === 'IFRAME') {
          var src = node.src || node.getAttribute('src');
          if (src && isVideoUrl(src)) {
            postResult(src, 'iframe', 'mutation_observer');
          }
        }
        if (node.querySelectorAll) {
          var frames = node.querySelectorAll('iframe');
          for (var j = 0; j < frames.length; j++) {
            var fsrc = frames[j].src || frames[j].getAttribute('src');
            if (fsrc && isVideoUrl(fsrc)) {
              postResult(fsrc, 'iframe', 'mutation_observer');
            }
          }
        }
      });
    });
  });

  function setupLegacy() {
    var root = document.body || document.documentElement;
    if (!root) {
      setTimeout(setupLegacy, 50);
      return;
    }
    observer.observe(root, {childList: true, subtree: true});
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupLegacy);
  } else {
    setupLegacy();
  }

  var origVideoSrcSetter = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (origVideoSrcSetter && origVideoSrcSetter.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(val) {
        if (val && isVideoUrl(val)) {
          postResult(val, 'video_src_setter', 'property_intercept');
        }
        origVideoSrcSetter.set.call(this, val);
      },
      get: origVideoSrcSetter.get,
      configurable: true
    });
  }

  function scanMediaElements(source) {
    var media = document.querySelectorAll('video, audio, source');
    for (var i = 0; i < media.length; i++) {
      var src = media[i].currentSrc || media[i].src || media[i].getAttribute('src');
      if (src && isVideoUrl(src)) {
        postResult(src, 'media_current_src', source);
      }
    }
  }

  scanMediaElements('initial_media_scan');
  var mediaScanCount = 0;
  var mediaScanTimer = setInterval(function() {
    scanMediaElements('media_poll');
    mediaScanCount++;
    if (mediaScanCount >= 30) clearInterval(mediaScanTimer);
  }, 500);

  console.log('[KazumiSniffer] Legacy (iframe) script injected');
})();
`;
  }

  static getModernSnifferScript(): string {
    return `
(function() {
  if (window.__kazumi_sniffer_injected) return;
  window.__kazumi_sniffer_injected = true;
  window.__kazumi_sniffed_results = [];

  function postResult(url, type, source) {
    window.__kazumi_sniffed_results.push({url: url, type: type, source: source, ts: Date.now()});
    console.log('[KazumiSniffer] postResult: ' + type + ' ' + source + ' ' + url.substring(0, 80));
    if (window.VideoBridgeDebug && window.VideoBridgeDebug.postMessage) {
      window.VideoBridgeDebug.postMessage(JSON.stringify({url: url, type: type, source: source}));
    } else if (window.jsBridge && window.jsBridge.postMessage) {
      window.jsBridge.postMessage(JSON.stringify({url: url, type: type, source: source}));
    }
  }

  function isVideoUrl(url) {
    if (!url) return false;
    var lower = url.toLowerCase();
    if (lower.indexOf('.m3u8') !== -1 || lower.indexOf('.mp4') !== -1 ||
        lower.indexOf('.flv') !== -1 || lower.indexOf('.mknvideo') !== -1 ||
        lower.indexOf('m3u8') !== -1) {
      return true;
    }
    return isLikelyExtensionlessMediaUrl(lower);
  }

  function isLikelyExtensionlessMediaUrl(lower) {
    if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) return false;
    var nonMediaDomains = ['byteimg.com', 'pstatp.com', 'douyinpic.com', 'snssdk.com'];
    for (var d = 0; d < nonMediaDomains.length; d++) {
      if (lower.indexOf(nonMediaDomains[d]) !== -1) return false;
    }
    var clean = lower.split('?')[0].split('#')[0];
    var nonMedia = ['.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json'];
    for (var i = 0; i < nonMedia.length; i++) {
      if (clean.lastIndexOf(nonMedia[i]) === clean.length - nonMedia[i].length) return false;
    }
    var hints = ['://v16', '://v26', '://v3', '://v6', '://v9', '://lf', '://lf2', '://lf3', '://lf6', '://lf9', '://lf20', '://vkc', '://vkce', '://fev', '://febo', '/video/tos/', 'videocdn', 'video-cdn', 'mcdn', 'bytecdntp', 'bytetos.com', 'csp-sign', 'tos-cn-v-', 'play.mknacg.top:9009/d/', 'tjdownload.pan.wo.cn', 'pan.wo.cn/openapi/download', '/openapi/download?fid=', '/videos/', '/videoplayback', '/videoplay', 'cdnvideo', 'cdn-video', 'hlsvideo', 'streaming', 'liveld'];
    for (var j = 0; j < hints.length; j++) {
      if (lower.indexOf(hints[j]) !== -1) return true;
    }
    return false;
  }

  function isM3u8Content(text) {
    return text && text.indexOf('#EXTM3U') !== -1;
  }

  function processVideoElement(video) {
    var src = video.getAttribute('src');
    if (src && src.trim() !== '' && !src.startsWith('blob:') && src.indexOf('googleads') === -1) {
      if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
        console.log('[KazumiSniffer] VIDEO src found: ' + src.substring(0, 80));
        postResult(src, 'video_tag', 'mutation_observer');
        return true;
      }
    }
    var sources = video.getElementsByTagName('source');
    for (var s = 0; s < sources.length; s++) {
      src = sources[s].getAttribute('src');
      if (src && src.trim() !== '' && !src.startsWith('blob:') && src.indexOf('googleads') === -1) {
        if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
          console.log('[KazumiSniffer] VIDEO source tag found: ' + src.substring(0, 80));
          postResult(src, 'video_tag', 'mutation_observer');
          return true;
        }
      }
    }
    return false;
  }

  function postUrlIfMedia(url, type, source) {
    if (!url || typeof url !== 'string') return false;
    if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return false;
    if (isVideoUrl(url) || ((url.indexOf('http://') === 0 || url.indexOf('https://') === 0) && url.indexOf('googleads') === -1)) {
      postResult(url, type, source);
      return true;
    }
    return false;
  }

  function inspectPlayerOptions(opts, source) {
    if (!opts || typeof opts !== 'object') return false;
    var keys = ['src', 'url', 'video', 'source', 'file'];
    var found = false;
    for (var i = 0; i < keys.length; i++) {
      var val = opts[keys[i]];
      if (typeof val === 'string') {
        found = postUrlIfMedia(val, 'player_config', source + '_' + keys[i]) || found;
      }
    }
    if (opts.parse && typeof opts.parse === 'object') {
      found = inspectPlayerOptions(opts.parse, source + '_parse') || found;
    }
    if (opts.sources && opts.sources.length) {
      for (var s = 0; s < opts.sources.length; s++) {
        var item = opts.sources[s];
        if (typeof item === 'string') {
          found = postUrlIfMedia(item, 'player_config', source + '_sources') || found;
        } else {
          found = inspectPlayerOptions(item, source + '_sources') || found;
        }
      }
    }
    return found;
  }

  function constructWithArgs(Ctor, args) {
    var bindArgs = [null];
    for (var i = 0; i < args.length; i++) bindArgs.push(args[i]);
    var Bound = Function.prototype.bind.apply(Ctor, bindArgs);
    return new Bound();
  }

  function wrapMuiPlayer(Ctor) {
    if (typeof Ctor !== 'function' || Ctor.__kazumi_wrapped) return Ctor;
    var Wrapped = function() {
      try {
        inspectPlayerOptions(arguments[0], 'mui_player_ctor');
      } catch(e) {}
      return constructWithArgs(Ctor, arguments);
    };
    try {
      Wrapped.prototype = Ctor.prototype;
      Wrapped.__kazumi_wrapped = true;
    } catch(e) {}
    return Wrapped;
  }

  function wrapPlayerFunction(fn) {
    if (typeof fn !== 'function' || fn.__kazumi_wrapped) return fn;
    var Wrapped = function() {
      try {
        inspectPlayerOptions(arguments[0], 'player_function');
      } catch(e) {}
      return fn.apply(this, arguments);
    };
    try {
      Wrapped.__kazumi_wrapped = true;
    } catch(e) {}
    return Wrapped;
  }

  function wrapHlsCtor(HlsCtor) {
    if (!HlsCtor || HlsCtor.__kazumi_wrapped) return HlsCtor;
    try {
      if (HlsCtor.prototype && typeof HlsCtor.prototype.loadSource === 'function' && !HlsCtor.prototype.loadSource.__kazumi_wrapped) {
        var origLoadSource = HlsCtor.prototype.loadSource;
        HlsCtor.prototype.loadSource = function(url) {
          try {
            postUrlIfMedia(url, 'hls_load_source', 'hls_load_source');
          } catch(e) {}
          return origLoadSource.apply(this, arguments);
        };
        HlsCtor.prototype.loadSource.__kazumi_wrapped = true;
      }
      HlsCtor.__kazumi_wrapped = true;
    } catch(e) {}
    return HlsCtor;
  }

  function installPlayerHooks() {
    try {
      var currentMui = window.MuiPlayer;
      if (currentMui) currentMui = wrapMuiPlayer(currentMui);
      Object.defineProperty(window, 'MuiPlayer', {
        configurable: true,
        get: function() {
          return currentMui;
        },
        set: function(v) {
          currentMui = wrapMuiPlayer(v);
        }
      });
      if (currentMui) window.MuiPlayer = currentMui;
    } catch(e) {
      try {
        if (window.MuiPlayer) window.MuiPlayer = wrapMuiPlayer(window.MuiPlayer);
      } catch(e2) {}
    }

    try {
      var currentPlayer = window.player;
      if (currentPlayer) currentPlayer = wrapPlayerFunction(currentPlayer);
      Object.defineProperty(window, 'player', {
        configurable: true,
        get: function() {
          return currentPlayer;
        },
        set: function(v) {
          currentPlayer = wrapPlayerFunction(v);
        }
      });
      if (currentPlayer) window.player = currentPlayer;
    } catch(e3) {
      try {
        if (window.player) window.player = wrapPlayerFunction(window.player);
      } catch(e4) {}
    }

    try {
      var currentHls = window.Hls;
      if (currentHls) currentHls = wrapHlsCtor(currentHls);
      Object.defineProperty(window, 'Hls', {
        configurable: true,
        get: function() {
          return currentHls;
        },
        set: function(v) {
          currentHls = wrapHlsCtor(v);
        }
      });
      if (currentHls) window.Hls = currentHls;
    } catch(e5) {
      try {
        if (window.Hls) window.Hls = wrapHlsCtor(window.Hls);
      } catch(e6) {}
    }
  }

  function nudgePlayback() {
    try {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        processVideoElement(videos[i]);
        videos[i].muted = true;
        var promise = videos[i].play && videos[i].play();
        if (promise && promise.catch) promise.catch(function() {});
      }
      var controls = document.querySelectorAll('.mui-player, .mui-player-video, .mui-player-play, .play, button');
      for (var c = 0; c < controls.length && c < 8; c++) {
        if (controls[c].click) controls[c].click();
      }
    } catch(e) {}
  }

  installPlayerHooks();
  var hookInstallCount = 0;
  var hookInstallTimer = setInterval(function() {
    installPlayerHooks();
    hookInstallCount++;
    if (hookInstallCount >= 40) clearInterval(hookInstallTimer);
  }, 250);

  var observer = new MutationObserver(function(mutations) {
    for (var m = 0; m < mutations.length; m++) {
      var mutation = mutations[m];
      if (mutation.type === 'attributes' && mutation.target && mutation.target.nodeName === 'VIDEO') {
        if (processVideoElement(mutation.target)) return;
        continue;
      }
      var addedNodes = mutation.addedNodes;
      for (var n = 0; n < addedNodes.length; n++) {
        var node = addedNodes[n];
        if (node.nodeName === 'VIDEO') {
          if (processVideoElement(node)) return;
        }
        if (node.querySelectorAll) {
          var videos = node.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            if (processVideoElement(videos[i])) return;
          }
        }
      }
    }
  });

  function setupModern() {
    var root = document.body || document.documentElement;
    if (!root) {
      setTimeout(setupModern, 50);
      return;
    }
    for (var i = 0; i < document.querySelectorAll('video').length; i++) {
      if (processVideoElement(document.querySelectorAll('video')[i])) return;
    }
    observer.observe(root, {childList: true, subtree: true, attributes: true, attributeFilter: ['src']});
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupModern);
  } else {
    setupModern();
  }

  function scanMediaElements(source) {
    var media = document.querySelectorAll('video, audio, source');
    for (var i = 0; i < media.length; i++) {
      var src = media[i].currentSrc || media[i].src || media[i].getAttribute('src');
      if (src && (isVideoUrl(src) || (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) && !src.startsWith('blob:'))) {
        postResult(src, 'media_current_src', source);
      }
    }
  }

  scanMediaElements('initial_media_scan');
  setTimeout(nudgePlayback, 300);
  setTimeout(function() {
    scanMediaElements('post_nudge_media_scan');
  }, 800);
  setTimeout(nudgePlayback, 1500);
  setTimeout(function() {
    scanMediaElements('late_post_nudge_media_scan');
  }, 2500);
  var mediaScanCount = 0;
  var mediaScanTimer = setInterval(function() {
    scanMediaElements('media_poll');
    mediaScanCount++;
    if (mediaScanCount >= 30) clearInterval(mediaScanTimer);
  }, 500);

  var origXhrOpen = XMLHttpRequest.prototype.open;
  var origXhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__kazumi_url = url;
    this.__kazumi_method = method;
    return origXhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function() {
    var self = this;
    if (self.__kazumi_url && isVideoUrl(self.__kazumi_url)) {
      postResult(self.__kazumi_url, 'xhr', 'xhr_intercept');
    }
    self.addEventListener('load', function() {
      try {
        var resp = self.responseText || self.response;
        if (typeof resp === 'string' && isM3u8Content(resp)) {
          postResult(self.__kazumi_url, 'm3u8_content', 'xhr_content_detect');
        }
      } catch(e) {}
    });
    return origXhrSend.apply(this, arguments);
  };

  var origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    if (url && isVideoUrl(url)) {
      postResult(url, 'fetch', 'fetch_intercept');
    }
    return origFetch.apply(this, arguments).then(function(response) {
      if (url && response && response.headers) {
        var ct = response.headers.get('content-type') || '';
        if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('mpegURL') !== -1) {
          postResult(url, 'm3u8_content', 'fetch_content_type');
        }
      }
      return response;
    });
  };

  var origVideoSrcSetter = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (origVideoSrcSetter && origVideoSrcSetter.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(val) {
        if (val && (isVideoUrl(val) || ((val.indexOf('http://') === 0 || val.indexOf('https://') === 0) && !val.startsWith('blob:')))) {
          postResult(val, 'video_src_setter', 'property_intercept');
        }
        origVideoSrcSetter.set.call(this, val);
      },
      get: origVideoSrcSetter.get,
      configurable: true
    });
  }

  console.log('[KazumiSniffer] Modern (video/fetch/XHR/m3u8) script injected');
})();
`;
  }

  static getVideoElementFallbackScript(): string {
    return `
(function() {
  var results = [];
  function pushUrl(url, type, source) {
    if (!url || typeof url !== 'string') return;
    if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return;
    if (url.indexOf('http://') === 0 || url.indexOf('https://') === 0) {
      results.push({url: url, type: type, source: source});
    }
  }
  function inspectOptions(opts, source) {
    if (!opts || typeof opts !== 'object') return;
    var keys = ['src', 'url', 'video', 'source', 'file'];
    for (var i = 0; i < keys.length; i++) {
      if (typeof opts[keys[i]] === 'string') pushUrl(opts[keys[i]], 'player_config', source + '_' + keys[i]);
    }
    if (opts.parse && typeof opts.parse === 'object') inspectOptions(opts.parse, source + '_parse');
    if (opts.sources && opts.sources.length) {
      for (var s = 0; s < opts.sources.length; s++) {
        if (typeof opts.sources[s] === 'string') {
          pushUrl(opts.sources[s], 'player_config', source + '_sources');
        } else {
          inspectOptions(opts.sources[s], source + '_sources');
        }
      }
    }
  }
  try {
    inspectOptions(window.config, 'window_config');
    inspectOptions(window.playerConfig, 'window_player_config');
    inspectOptions(window.videoConfig, 'window_video_config');
  } catch(e) {}
  var videos = document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    var v = videos[i];
    var src = v.currentSrc || v.src || v.getAttribute('src');
    pushUrl(src, 'video_element', 'video_element_fallback');
    try {
      v.muted = true;
      var promise = v.play && v.play();
      if (promise && promise.catch) promise.catch(function() {});
    } catch(e) {}
    var sources = v.querySelectorAll('source');
    for (var j = 0; j < sources.length; j++) {
      var ssrc = sources[j].src || sources[j].getAttribute('src');
      pushUrl(ssrc, 'video_source_element', 'video_element_fallback');
    }
  }
  try {
    var controls = document.querySelectorAll('.mui-player, .mui-player-video, .mui-player-play, .play, button');
    for (var ci = 0; ci < controls.length && ci < 8; ci++) {
      if (controls[ci].click) controls[ci].click();
    }
  } catch(e) {}
  if (results.length === 0 && window.performance && window.performance.getEntriesByType) {
    try {
      var entries = window.performance.getEntriesByType('resource');
      var hints = ['.m3u8', '.mp4', '.flv', '.mknvideo', 'm3u8', 'mp4', '://v1', '://v2', '://v3', '://lf', '://lf2', '://lf6', '://vkc', '/video/tos/', 'videocdn', 'video-cdn', 'mcdn', 'bytecdntp', 'bytetos.com', 'csp-sign', 'play.mknacg.top:9009/d/', 'tjdownload.pan.wo.cn', 'pan.wo.cn/openapi/download', '/openapi/download?fid=', '/videos/', 'cdnvideo', 'streaming'];
      for (var k = entries.length - 1; k >= 0; k--) {
        var e = entries[k];
        var eurl = e.name || '';
        var elower = eurl.toLowerCase();
        for (var h = 0; h < hints.length; h++) {
          if (elower.indexOf(hints[h]) !== -1) {
            results.push({url: eurl, type: 'performance_resource', source: 'video_element_fallback'});
            break;
          }
        }
      }
    } catch(e) {}
  }
  console.log('[KazumiSniffer] Fallback scan found ' + results.length + ' candidates');
  for (var r = 0; r < results.length; r++) {
    console.log('[KazumiSniffer] Fallback: ' + results[r].url.substring(0, 80));
  }
  if (results.length > 0) {
    for (var r = 0; r < results.length; r++) {
      if (window.VideoBridgeDebug && window.VideoBridgeDebug.postMessage) {
        window.VideoBridgeDebug.postMessage(JSON.stringify(results[r]));
      } else if (window.JSBridgeDebug && window.JSBridgeDebug.postMessage) {
        window.JSBridgeDebug.postMessage(JSON.stringify(results[r]));
      } else if (window.jsBridge && window.jsBridge.postMessage) {
        window.jsBridge.postMessage(JSON.stringify(results[r]));
      }
    }
  }
})();
`;
  }

  static getScriptHash(): string {
    return JSInjector.SCRIPT_HASH
  }

  static validateScriptHash(hash: string): boolean {
    return hash === JSInjector.SCRIPT_HASH
  }
}
