(async function () {
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

    // When opened via file://, absolute paths like /_components/header.html resolve to disk root
    // and usually fail. Try depth-based relative fallbacks.
    if (window.location && window.location.protocol === 'file:') {
      var parts = window.location.pathname.replace(/\\/g, '/').split('/').filter(Boolean);
      var depth = Math.max(parts.length - 1, 0);
      var maxDepth = Math.min(depth + 2, 8);

      for (var i = 0; i <= maxDepth; i++) {
        var prefix = i === 0 ? './' : new Array(i + 1).join('../');
        candidates.push(prefix + cleanPath);
      }
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
    try {
      var candidates = buildFragmentCandidates(fragmentPath);
      var html = await fetchFirstAvailable(candidates);
      if (!html) {
        if (window.location && window.location.protocol === 'file:' && placeholderSelector === '[data-component="site-header"]') {
          placeholder.innerHTML = '<div style="padding:12px 16px;border:1px solid #d9d9d9;background:#fffbe6;color:#8a6d3b;font-size:13px;">Topbar 元件在 file:// 模式無法載入，請改用本機伺服器開啟（例如 http://localhost）。</div>';
        }
        if (window.console && console.warn) {
          console.warn('Component load failed:', placeholderSelector, candidates);
        }
        return;
      }
      var wrap = document.createElement("div");
      wrap.innerHTML = html;
      var node = wrap.firstElementChild;
      if (!node) return;
      placeholder.replaceWith(node);
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

  await hydrate('[data-component="site-header"]', '/_components/header.html');
  await hydrate('[data-component="site-footer"]', '/_components/footer.html');

  // Run once now and once shortly after to cover late inline script init order.
  applyScopedSwiperFix();
  setTimeout(applyScopedSwiperFix, 120);
})();