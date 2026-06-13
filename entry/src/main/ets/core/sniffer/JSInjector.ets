export class JSInjector {
  private static SCRIPT_HASH: string = 'BUILTIN_SNIFFER_V2'

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
        lower.indexOf('.flv') !== -1 || lower.indexOf('m3u8') !== -1) {
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
    var hints = ['://v16', '://v26', '://v3', '://v6', '://v9', '/video/tos/', 'videocdn', 'video-cdn', 'mcdn', 'bytecdntp'];
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
  observer.observe(document.documentElement, {childList: true, subtree: true});

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
        lower.indexOf('.flv') !== -1 || lower.indexOf('m3u8') !== -1) {
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
    var hints = ['://v16', '://v26', '://v3', '://v6', '://v9', '/video/tos/', 'videocdn', 'video-cdn', 'mcdn', 'bytecdntp'];
    for (var j = 0; j < hints.length; j++) {
      if (lower.indexOf(hints[j]) !== -1) return true;
    }
    return false;
  }

  function isM3u8Content(text) {
    return text && text.indexOf('#EXTM3U') !== -1;
  }

  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeName === 'VIDEO' || node.nodeName === 'SOURCE') {
          var src = node.src || node.getAttribute('src');
          if (src && isVideoUrl(src)) {
            postResult(src, 'video_tag', 'mutation_observer');
          }
        }
        if (node.querySelectorAll) {
          var videos = node.querySelectorAll('video, source');
          for (var i = 0; i < videos.length; i++) {
            var vsrc = videos[i].src || videos[i].getAttribute('src');
            if (vsrc && isVideoUrl(vsrc)) {
              postResult(vsrc, 'video_tag', 'mutation_observer');
            }
          }
        }
      });
    });
  });
  observer.observe(document.documentElement, {childList: true, subtree: true});

  var existingVideos = document.querySelectorAll('video, source');
  for (var i = 0; i < existingVideos.length; i++) {
    var esrc = existingVideos[i].src || existingVideos[i].getAttribute('src');
    if (esrc && isVideoUrl(esrc)) {
      postResult(esrc, 'video_tag', 'initial_scan');
    }
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
        if (val && isVideoUrl(val)) {
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

  static getScriptHash(): string {
    return JSInjector.SCRIPT_HASH
  }

  static validateScriptHash(hash: string): boolean {
    return hash === JSInjector.SCRIPT_HASH
  }
}
