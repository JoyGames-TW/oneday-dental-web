(async function () {
  async function hydrate(placeholderSelector, fragmentPath) {
    var placeholder = document.querySelector(placeholderSelector);
    if (!placeholder) return;
    try {
      var res = await fetch(fragmentPath, { cache: "no-store" });
      if (!res.ok) return;
      var html = await res.text();
      var wrap = document.createElement("div");
      wrap.innerHTML = html;
      var node = wrap.firstElementChild;
      if (!node) return;
      placeholder.replaceWith(node);
    } catch (e) {
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