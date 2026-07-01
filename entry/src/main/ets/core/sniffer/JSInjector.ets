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

  function postResult(url, type, source, extra) {
    var msg = {url: url, type: type, source: source};
    if (extra) {
      if (extra.referer) msg.referer = extra.referer;
      if (extra.cookie) msg.cookie = extra.cookie;
      if (extra.contentType) msg.contentType = extra.contentType;
      if (extra.hasRange) msg.hasRange = 'true';
      if (extra.headers) msg.headers = JSON.stringify(extra.headers);
    }
    window.__kazumi_sniffed_results.push({url: url, type: type, source: source, ts: Date.now()});
    console.log('[KazumiSniffer] postResult: ' + type + ' ' + source + ' ' + url.substring(0, 80));
    if (window.JSBridgeDebug && window.JSBridgeDebug.postMessage) {
      window.JSBridgeDebug.postMessage(JSON.stringify(msg));
    } else if (window.jsBridge && window.jsBridge.postMessage) {
      window.jsBridge.postMessage(JSON.stringify(msg));
    }
  }

  function getSnifferExtra() {
    var extra = {};
    try { extra.referer = document.referrer || ''; } catch(e) { extra.referer = ''; }
    try { extra.cookie = document.cookie || ''; } catch(e) { extra.cookie = ''; }
    return extra;
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
      var extra = getSnifferExtra();
      postResult(iframeSrc, 'iframe', 'iframe_scan', extra);
    }
  }

  window.addEventListener('message', function(event) {
    try {
      var data = JSON.parse(event.data);
      if (data && data.__kazumi_sniff && data.url) {
        var extra = getSnifferExtra();
        postResult(data.url, data.type || 'unknown', data.source || 'iframe_postmessage', extra);
      }
    } catch(e) {}
  });

  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeName === 'IFRAME') {
          var src = node.src || node.getAttribute('src');
          if (src && isVideoUrl(src)) {
            var extra = getSnifferExtra();
            postResult(src, 'iframe', 'mutation_observer', extra);
          }
        }
        if (node.querySelectorAll) {
          var frames = node.querySelectorAll('iframe');
          for (var j = 0; j < frames.length; j++) {
            var fsrc = frames[j].src || frames[j].getAttribute('src');
            if (fsrc && isVideoUrl(fsrc)) {
              var extra = getSnifferExtra();
              postResult(fsrc, 'iframe', 'mutation_observer', extra);
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
          var extra = getSnifferExtra();
          postResult(val, 'video_src_setter', 'property_intercept', extra);
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
        var extra = getSnifferExtra();
        postResult(src, 'media_current_src', source, extra);
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

  function postResult(url, type, source, extra) {
    var msg = {url: url, type: type, source: source};
    if (extra) {
      if (extra.referer) msg.referer = extra.referer;
      if (extra.cookie) msg.cookie = extra.cookie;
      if (extra.contentType) msg.contentType = extra.contentType;
      if (extra.hasRange) msg.hasRange = 'true';
      if (extra.headers) msg.headers = JSON.stringify(extra.headers);
    }
    window.__kazumi_sniffed_results.push({url: url, type: type, source: source, ts: Date.now()});
    console.log('[KazumiSniffer] postResult: ' + type + ' ' + source + ' ' + url.substring(0, 80));
    if (window.VideoBridgeDebug && window.VideoBridgeDebug.postMessage) {
      window.VideoBridgeDebug.postMessage(JSON.stringify(msg));
    } else if (window.jsBridge && window.jsBridge.postMessage) {
      window.jsBridge.postMessage(JSON.stringify(msg));
    }
  }

  function getSnifferExtra() {
    var extra = {};
    try { extra.referer = document.referrer || ''; } catch(e) { extra.referer = ''; }
    try { extra.cookie = document.cookie || ''; } catch(e) { extra.cookie = ''; }
    return extra;
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

  var videoMimeTypes = [
    'mpegurl', 'mpegURL', 'video/mp4', 'video/flv', 'video/x-flv',
    'video/f4v', 'video/MP2T', 'video/webm', 'video/quicktime',
    'video/x-msvideo', 'video/x-matroska', 'video/3gpp',
    'application/x-mpegURL', 'application/vnd.apple.mpegurl',
    'application/octet-stream'
  ];

  function isVideoMimeType(ct) {
    if (!ct) return false;
    var lower = ct.toLowerCase();
    for (var v = 0; v < videoMimeTypes.length; v++) {
      if (lower.indexOf(videoMimeTypes[v].toLowerCase()) !== -1) return true;
    }
    return false;
  }

  function headersToObject(headers) {
    var out = {};
    if (!headers) return out;
    try {
      if (headers.forEach && typeof headers.forEach === 'function') {
        headers.forEach(function(value, key) {
          out[String(key)] = String(value);
        });
        return out;
      }
      if (headers.length && typeof headers !== 'string') {
        for (var i = 0; i < headers.length; i++) {
          if (headers[i] && headers[i].length >= 2) out[String(headers[i][0])] = String(headers[i][1]);
        }
        return out;
      }
      if (typeof headers === 'object') {
        var keys = Object.keys(headers);
        for (var k = 0; k < keys.length; k++) {
          out[String(keys[k])] = String(headers[keys[k]]);
        }
      }
    } catch(e) {}
    return out;
  }

  function mergeHeaders(target, source) {
    if (!source) return target || {};
    target = target || {};
    try {
      var keys = Object.keys(source);
      for (var i = 0; i < keys.length; i++) {
        target[keys[i]] = source[keys[i]];
      }
    } catch(e) {}
    return target;
  }

  function hasHeader(headers, name) {
    if (!headers) return false;
    var target = name.toLowerCase();
    try {
      var keys = Object.keys(headers);
      for (var i = 0; i < keys.length; i++) {
        if (String(keys[i]).toLowerCase() === target) return true;
      }
    } catch(e) {}
    return false;
  }

  function inspectM3u8Text(url, text, contentType, source) {
    try {
      if (url && typeof text === 'string' && isM3u8Content(text)) {
        var extra = getSnifferExtra();
        if (contentType) extra.contentType = contentType;
        postResult(url, 'm3u8_content', source, extra);
        return true;
      }
    } catch(e) {}
    return false;
  }

  try {
    if (window.Response && window.Response.prototype && window.Response.prototype.text &&
        !window.Response.prototype.text.__kazumi_wrapped) {
      var origResponseText = window.Response.prototype.text;
      window.Response.prototype.text = function() {
        var response = this;
        return origResponseText.apply(this, arguments).then(function(text) {
          try {
            var url = response && response.url ? response.url : '';
            var ct = response && response.headers ? (response.headers.get('content-type') || '') : '';
            inspectM3u8Text(url, text, ct, 'response_text');
          } catch(e) {}
          return text;
        });
      };
      window.Response.prototype.text.__kazumi_wrapped = true;
    }
  } catch(e) {}

  function processVideoElement(video) {
    var src = video.getAttribute('src');
    if (src && src.trim() !== '' && !src.startsWith('blob:') && src.indexOf('googleads') === -1) {
      if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
        console.log('[KazumiSniffer] VIDEO src found: ' + src.substring(0, 80));
        var extra = getSnifferExtra();
        postResult(src, 'video_tag', 'mutation_observer', extra);
        return true;
      }
    }
    var sources = video.getElementsByTagName('source');
    for (var s = 0; s < sources.length; s++) {
      src = sources[s].getAttribute('src');
      if (src && src.trim() !== '' && !src.startsWith('blob:') && src.indexOf('googleads') === -1) {
        if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
          console.log('[KazumiSniffer] VIDEO source tag found: ' + src.substring(0, 80));
          var extra = getSnifferExtra();
          postResult(src, 'video_tag', 'mutation_observer', extra);
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
      var extra = getSnifferExtra();
      postResult(url, type, source, extra);
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

  var iframeSnifferScript = null;

  function getIframeSnifferScript() {
    if (iframeSnifferScript) return iframeSnifferScript;
    iframeSnifferScript = '(' + function() {
      if (window.__kazumi_iframe_sniffer_injected) return;
      window.__kazumi_iframe_sniffer_injected = true;
      function postToParent(url, type, source) {
        var msg = {__kazumi_sniff: true, url: url, type: type, source: source};
        try {
          if (window.parent && window.parent !== window) {
            window.parent.postMessage(JSON.stringify(msg), '*');
          }
        } catch(e) {}
        try {
          if (window.VideoBridgeDebug && window.VideoBridgeDebug.postMessage) {
            window.VideoBridgeDebug.postMessage(JSON.stringify(msg));
          } else if (window.jsBridge && window.jsBridge.postMessage) {
            window.jsBridge.postMessage(JSON.stringify(msg));
          }
        } catch(e2) {}
      }
      function isVUrl(url) {
        if (!url) return false;
        var lower = url.toLowerCase();
        if (lower.indexOf('.m3u8') !== -1 || lower.indexOf('.mp4') !== -1 ||
            lower.indexOf('.flv') !== -1 || lower.indexOf('.mknvideo') !== -1) return true;
        return false;
      }
      var origXhrOpen = XMLHttpRequest.prototype.open;
      var origXhrSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__kazumi_url = url;
        return origXhrOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        var self = this;
        if (self.__kazumi_url && isVUrl(self.__kazumi_url)) {
          postToParent(self.__kazumi_url, 'xhr', 'iframe_xhr');
        }
        self.addEventListener('load', function() {
          try {
            var resp = self.responseText || self.response;
            if (typeof resp === 'string' && resp.indexOf('#EXTM3U') !== -1) {
              postToParent(self.__kazumi_url, 'm3u8_content', 'iframe_xhr_content');
            }
          } catch(e) {}
        });
        return origXhrSend.apply(this, arguments);
      };
      var origFetch = window.fetch;
      window.fetch = function(input, init) {
        var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
        if (url && isVUrl(url)) {
          postToParent(url, 'fetch', 'iframe_fetch');
        }
        return origFetch.apply(this, arguments).then(function(response) {
          if (url && response && response.headers) {
            var ct = response.headers.get('content-type') || '';
            if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('mpegURL') !== -1 ||
                ct.indexOf('video/') !== -1) {
              postToParent(url, 'video_content_type', 'iframe_fetch_ct');
            }
          }
          return response;
        });
      };
      var origSrcSetter = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
      if (origSrcSetter && origSrcSetter.set) {
        Object.defineProperty(HTMLMediaElement.prototype, 'src', {
          set: function(val) {
            if (val && isVUrl(val)) postToParent(val, 'video_src_setter', 'iframe_src_setter');
            origSrcSetter.set.call(this, val);
          },
          get: origSrcSetter.get,
          configurable: true
        });
      }
      function scanVideos() {
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var src = videos[i].currentSrc || videos[i].src || videos[i].getAttribute('src');
          if (src && isVUrl(src)) postToParent(src, 'video_tag', 'iframe_video_scan');
        }
      }
      scanVideos();
      setInterval(scanVideos, 1000);
      console.log('[KazumiSniffer] iframe sniffer injected');
    } + ')();';
    return iframeSnifferScript;
  }

  function tryInjectIframe(iframe) {
    try {
      if (iframe.__kazumi_injected) return;
      iframe.__kazumi_injected = true;
      var src = iframe.src || iframe.getAttribute('src') || '';
      if (src.indexOf('http://') !== 0 && src.indexOf('https://') !== 0) return;
      if (src.indexOf('googleads') !== -1 || src.indexOf('doubleclick') !== -1) return;
      var script = getIframeSnifferScript();
      try {
        var iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
        if (iframeDoc && !iframe.__kazumi_script_added) {
          var s = iframeDoc.createElement('script');
          s.textContent = script;
          s.setAttribute('data-kazumi-sniffer', 'true');
          (iframeDoc.head || iframeDoc.documentElement).appendChild(s);
          iframe.__kazumi_script_added = true;
          console.log('[KazumiSniffer] Injected into same-origin iframe: ' + src.substring(0, 60));
        }
      } catch(e) {
        console.log('[KazumiSniffer] Cross-origin iframe, relying on postMessage: ' + src.substring(0, 60));
      }
    } catch(e2) {}
  }

  window.addEventListener('message', function(event) {
    try {
      var data = JSON.parse(event.data);
      if (data && data.__kazumi_sniff && data.url) {
        var extra = getSnifferExtra();
        postResult(data.url, data.type || 'unknown', data.source || 'iframe_postmessage', extra);
      }
    } catch(e) {}
  });

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
        if (node.nodeName === 'IFRAME') {
          tryInjectIframe(node);
        }
        if (node.querySelectorAll) {
          var videos = node.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            if (processVideoElement(videos[i])) return;
          }
          var iframes = node.querySelectorAll('iframe');
          for (var j = 0; j < iframes.length; j++) {
            tryInjectIframe(iframes[j]);
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
    var existingIframes = document.querySelectorAll('iframe');
    for (var fi = 0; fi < existingIframes.length; fi++) {
      tryInjectIframe(existingIframes[fi]);
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
        var extra = getSnifferExtra();
        postResult(src, 'media_current_src', source, extra);
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
  var origXhrSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
  var origXhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__kazumi_url = url;
    this.__kazumi_method = method;
    this.__kazumi_headers = {};
    return origXhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    try {
      this.__kazumi_headers = this.__kazumi_headers || {};
      this.__kazumi_headers[String(name)] = String(value);
    } catch(e) {}
    return origXhrSetRequestHeader.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function() {
    var self = this;
    var url = self.__kazumi_url;
    var xhrHeaders = self.__kazumi_headers || {};
    if (url && isVideoUrl(url)) {
      var extra = getSnifferExtra();
      extra.headers = xhrHeaders;
      if (hasHeader(xhrHeaders, 'range')) extra.hasRange = true;
      postResult(url, 'xhr', 'xhr_intercept', extra);
    }
    self.addEventListener('load', function() {
      try {
        var ct = self.getResponseHeader('Content-Type') || '';
        if (ct && isVideoMimeType(ct)) {
          var extra = getSnifferExtra();
          extra.contentType = ct;
          extra.headers = xhrHeaders;
          if (hasHeader(xhrHeaders, 'range')) extra.hasRange = true;
          postResult(url, 'video_content_type', 'xhr_content_type', extra);
          return;
        }
        var resp = self.responseText || self.response;
        if (typeof resp === 'string' && isM3u8Content(resp)) {
          var extra2 = getSnifferExtra();
          extra2.contentType = ct;
          extra2.headers = xhrHeaders;
          if (hasHeader(xhrHeaders, 'range')) extra2.hasRange = true;
          postResult(url, 'm3u8_content', 'xhr_content_detect', extra2);
        }
      } catch(e) {}
    });
    return origXhrSend.apply(this, arguments);
  };

  var origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    var requestHeaders = {};
    try {
      if (input && typeof input === 'object' && input.headers) {
        requestHeaders = mergeHeaders(requestHeaders, headersToObject(input.headers));
      }
      if (init && init.headers) {
        requestHeaders = mergeHeaders(requestHeaders, headersToObject(init.headers));
      }
    } catch(e) {}
    var hasRange = hasHeader(requestHeaders, 'range');
    if (init && init.headers) {
      try {
        if (typeof init.headers === 'object') {
          var hKeys = Object.keys(init.headers);
          for (var hk = 0; hk < hKeys.length; hk++) {
            if (hKeys[hk].toLowerCase() === 'range') { hasRange = true; break; }
          }
        }
      } catch(e) {}
    }
    if (url && isVideoUrl(url)) {
      var extra = getSnifferExtra();
      if (hasRange) extra.hasRange = true;
      extra.headers = requestHeaders;
      postResult(url, 'fetch', 'fetch_intercept', extra);
    }
    return origFetch.apply(this, arguments).then(function(response) {
      if (url && response && response.headers) {
        var ct = response.headers.get('content-type') || '';
        if (isVideoMimeType(ct)) {
          var extra = getSnifferExtra();
          extra.contentType = ct;
          if (hasRange) extra.hasRange = true;
          extra.headers = requestHeaders;
          postResult(url, 'video_content_type', 'fetch_content_type', extra);
        } else if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('mpegURL') !== -1) {
          var extra2 = getSnifferExtra();
          extra2.contentType = ct;
          if (hasRange) extra2.hasRange = true;
          extra2.headers = requestHeaders;
          postResult(url, 'm3u8_content', 'fetch_content_type', extra2);
        }
        if (response.clone && (isVideoUrl(url) || ct.indexOf('text/plain') !== -1 ||
            ct.indexOf('application/json') !== -1 || ct.indexOf('application/octet-stream') !== -1)) {
          try {
            response.clone().text().then(function(text) {
              inspectM3u8Text(url, text, ct, 'fetch_response_text');
            }).catch(function() {});
          } catch(e3) {}
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
          var extra = getSnifferExtra();
          postResult(val, 'video_src_setter', 'property_intercept', extra);
        }
        origVideoSrcSetter.set.call(this, val);
      },
      get: origVideoSrcSetter.get,
      configurable: true
    });
  }

  console.log('[KazumiSniffer] Modern (video/fetch/XHR/m3u8/iframe/postMessage) script injected');
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

  static extractHeadersFromJson(headerJson: string): Record<string, string> {
    let headers: Record<string, string> = {}
    if (headerJson.length === 0) {
      return headers
    }
    try {
      let parsed = JSON.parse(headerJson) as Record<string, string>
      let keys = Object.keys(parsed)
      for (let i = 0; i < keys.length; i++) {
        headers[keys[i]] = parsed[keys[i]]
      }
    } catch (e) {
    }
    return headers
  }
}
