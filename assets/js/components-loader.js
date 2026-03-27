(async function () {
  var COMPONENT_CACHE_VERSION = '2026-03-27';
  var COMPONENT_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

  function getComponentCacheKey(fragmentPath) {
    return 'component-html::' + COMPONENT_CACHE_VERSION + '::' + String(fragmentPath || '');
  }

  function readCachedComponent(fragmentPath) {
    try {
      if (!window.localStorage) return null;
      var raw = window.localStorage.getItem(getComponentCacheKey(fragmentPath));
      if (!raw) return null;

      var parsed = JSON.parse(raw);
      if (!parsed || typeof parsed.html !== 'string') return null;
      if (typeof parsed.expiresAt === 'number' && Date.now() > parsed.expiresAt) return null;

      return parsed.html;
    } catch (e) {
      return null;
    }
  }

  function writeCachedComponent(fragmentPath, html) {
    try {
      if (!window.localStorage || typeof html !== 'string' || !html) return;

      var payload = {
        html: html,
        expiresAt: Date.now() + COMPONENT_CACHE_TTL_MS
      };

      window.localStorage.setItem(getComponentCacheKey(fragmentPath), JSON.stringify(payload));
    } catch (e) {
    }
  }

  function normalizeBasePath(pathname) {
    if (!pathname || pathname === '/') return '';
    return '/' + String(pathname).replace(/^\/+|\/+$/g, '');
  }

  function detectSiteBasePath() {
    var marker = '/assets/js/components-loader.js';
    var scripts = document.getElementsByTagName('script');

    for (var i = scripts.length - 1; i >= 0; i--) {
      var src = scripts[i].getAttribute('src') || scripts[i].src;
      if (!src) continue;

      try {
        var url = new URL(src, window.location.href);
        var pathname = String(url.pathname || '');
        var markerIndex = pathname.lastIndexOf(marker);
        if (markerIndex === -1) continue;

        return normalizeBasePath(pathname.slice(0, markerIndex));
      } catch (e) {
      }
    }

    return '';
  }

  function getCurrentPathDepth() {
    if (!window.location || !window.location.pathname) return 0;

    var parts = window.location.pathname.replace(/\\/g, '/').split('/').filter(Boolean);
    if (!parts.length) return 0;

    var lastPart = parts[parts.length - 1];
    if (lastPart.indexOf('.') !== -1) {
      return Math.max(parts.length - 1, 0);
    }

    return parts.length;
  }

  function rewriteRootRelativeUrls(rootEl, basePath) {
    if (!rootEl || !basePath) return;

    var attrs = ['href', 'src', 'action', 'poster'];
    var selector = attrs.map(function (attr) {
      return '[' + attr + ']';
    }).join(',');

    function rewrite(el) {
      for (var i = 0; i < attrs.length; i++) {
        var attr = attrs[i];
        var value = el.getAttribute(attr);
        if (!value) continue;

        value = value.trim();
        if (!value || value.charAt(0) !== '/') continue;
        if (value.indexOf('//') === 0) continue;
        if (value === basePath || value.indexOf(basePath + '/') === 0) continue;

        el.setAttribute(attr, basePath + value);
      }
    }

    if (rootEl.matches && rootEl.matches(selector)) {
      rewrite(rootEl);
    }

    rootEl.querySelectorAll(selector).forEach(rewrite);
  }

  var SITE_BASE_PATH = detectSiteBasePath();

  function unique(arr) {
    var seen = {};
    return arr.filter(function (item) {
      if (seen[item]) return false;
      seen[item] = true;
      return true;
    });
  }

  function buildFragmentCandidates(fragmentPath) {
    var candidates = [fragmentPath];
    var cleanPath = String(fragmentPath || '').replace(/^\/+/, '');
    if (!cleanPath) return candidates;

    if (SITE_BASE_PATH) {
      candidates.push(SITE_BASE_PATH + '/' + cleanPath);
    }

    // Try depth-based relative fallbacks so nested pages can locate shared components.
    var depth = getCurrentPathDepth();
    var maxDepth = Math.min(depth + 2, 10);

    for (var i = 0; i <= maxDepth; i++) {
      var prefix = i === 0 ? './' : new Array(i + 1).join('../');
      candidates.push(prefix + cleanPath);
    }

    // When opened via file://, absolute paths like /_components/header.html resolve to disk root
    // and usually fail. Try depth-based relative fallbacks.
    if (window.location && window.location.protocol === 'file:') {
      candidates.push('/' + cleanPath);
    }

    return unique(candidates);
  }

  async function fetchFirstAvailable(paths) {
    for (var i = 0; i < paths.length; i++) {
      var path = paths[i];
      try {
        var res = await fetch(path, { cache: 'no-store' });
        if (!res.ok) continue;
        return await res.text();
      } catch (e) {
      }
    }
    return null;
  }

  async function hydrate(placeholderSelector, fragmentPath) {
    var placeholder = document.querySelector(placeholderSelector);
    if (!placeholder) return;

    var cachedHtml = readCachedComponent(fragmentPath);

    function mount(html) {
      if (!html || !placeholder.parentNode) return false;

      var wrap = document.createElement("div");
      wrap.innerHTML = html;
      rewriteRootRelativeUrls(wrap, SITE_BASE_PATH);

      var node = wrap.firstElementChild;
      if (!node) return false;

      placeholder.replaceWith(node);
      return true;
    }

    try {
      var mountedFromCache = false;
      if (cachedHtml) {
        mountedFromCache = mount(cachedHtml);
      }

      var candidates = buildFragmentCandidates(fragmentPath);
      var html = await fetchFirstAvailable(candidates);

      if (html) {
        writeCachedComponent(fragmentPath, html);
      }

      if (mountedFromCache) {
        return;
      }

      if (!html) {
        if (window.location && window.location.protocol === 'file:' && placeholderSelector === '[data-component="site-header"]') {
          placeholder.innerHTML = '<div style="padding:12px 16px;border:1px solid #d9d9d9;background:#fffbe6;color:#8a6d3b;font-size:13px;">Topbar 元件在 file:// 模式無法載入，請改用本機伺服器開啟（例如 http://localhost）。</div>';
        }
        if (window.console && console.warn) {
          console.warn('Component load failed:', placeholderSelector, candidates);
        }
        return;
      }

      mount(html);
    } catch (e) {
      if (window.console && console.warn) {
        console.warn('Hydrate failed:', placeholderSelector, fragmentPath, e);
      }
    }
  }

  function cloneWithoutListeners(node) {
    if (!node || !node.parentNode) return node;
    var cloned = node.cloneNode(true);
    node.parentNode.replaceChild(cloned, node);
    return cloned;
  }

  function findNavContainer(swiperEl) {
    var container = swiperEl.parentElement;
    while (container && container !== document.body) {
      if (container.querySelector('.swiper-button-next') || container.querySelector('.swiper-button-prev')) {
        return container;
      }
      container = container.parentElement;
    }
    return null;
  }

  function initScopedSwiper(selector, options) {
    if (typeof window.Swiper === 'undefined') return;

    document.querySelectorAll(selector).forEach(function (swiperEl) {
      var navContainer = findNavContainer(swiperEl);
      if (!navContainer) return;

      var nextBtn = navContainer.querySelector('.swiper-button-next');
      var prevBtn = navContainer.querySelector('.swiper-button-prev');

      // Remove old listeners from globally-bound buttons.
      nextBtn = cloneWithoutListeners(nextBtn);
      prevBtn = cloneWithoutListeners(prevBtn);

      // Destroy previously initialized instance to avoid duplicate controls.
      if (swiperEl.swiper && typeof swiperEl.swiper.destroy === 'function') {
        swiperEl.swiper.destroy(true, true);
      }

      var config = Object.assign({}, options, {
        navigation: {
          nextEl: nextBtn || null,
          prevEl: prevBtn || null
        }
      });

      new window.Swiper(swiperEl, config);
    });
  }

  function applyScopedSwiperFix() {
    initScopedSwiper('.footer_address', {
      slidesPerView: 3,
      spaceBetween: 30,
      loop: true
    });

    initScopedSwiper('.cases_swiper', {
      slidesPerView: 4,
      spaceBetween: 20,
      loop: true,
      autoplay: {
        delay: 3000,
        disableOnInteraction: false
      },
      breakpoints: {
        0: { slidesPerView: 2 },
        768: { slidesPerView: 3 }
      }
    });

    initScopedSwiper('.yt_swiper', {
      slidesPerView: 3,
      spaceBetween: 30,
      loop: true,
      autoplay: {
        delay: 4000,
        disableOnInteraction: false
      },
      breakpoints: {
        0: { slidesPerView: 2 },
        768: { slidesPerView: 3 }
      }
    });

    initScopedSwiper('.blog_swiper', {
      slidesPerView: 3,
      spaceBetween: 20,
      loop: true,
      autoplay: {
        delay: 5000,
        disableOnInteraction: false
      },
      breakpoints: {
        0: { slidesPerView: 1 },
        768: { slidesPerView: 3 }
      }
    });

    initScopedSwiper('.certificates_swiper', {
      slidesPerView: 3,
      spaceBetween: 10,
      loop: true,
      autoplay: {
        delay: 6000,
        disableOnInteraction: false
      },
      breakpoints: {
        0: { slidesPerView: 2 },
        768: { slidesPerView: 3 }
      }
    });

    initScopedSwiper('.recommend_swiper', {
      slidesPerView: 3,
      spaceBetween: 20,
      loop: true,
      autoplay: {
        delay: 6000,
        disableOnInteraction: false
      },
      breakpoints: {
        0: { slidesPerView: 1 },
        768: { slidesPerView: 3 }
      }
    });
  }

  await Promise.all([
    hydrate('[data-component="site-header"]', '_components/header.html'),
    hydrate('[data-component="site-footer"]', '_components/footer.html')
  ]);

  // Run once now and once shortly after to cover late inline script init order.
  applyScopedSwiperFix();
  setTimeout(applyScopedSwiperFix, 120);
})();