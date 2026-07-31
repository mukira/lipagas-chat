// planna-spinner.js — Comprehensive & Bulletproof Spinner Color Interceptor
(function () {
  'use strict';

  var BLUE = '#2563EB';

  function isPurple(colorStr) {
    if (!colorStr) return false;
    var s = colorStr.toLowerCase();
    return s.indexOf('612bd3') !== -1 ||
           s.indexOf('612ad5') !== -1 ||
           s.indexOf('97, 43, 211') !== -1 ||
           s.indexOf('97, 42, 213') !== -1 ||
           s.indexOf('96, 43, 211') !== -1 ||
           s.indexOf('123, 63, 242') !== -1 ||
           s.indexOf('7b3ff2') !== -1;
  }

  function fixElement(el) {
    if (!el || el.nodeType !== 1) return;

    var styleAttr = el.getAttribute('style') || '';
    var className = el.getAttribute('class') || '';

    // Case 1: Class-based spinner (.animate-spin or border-[#612BD3])
    if (className.indexOf('animate-spin') !== -1 || isPurple(className)) {
      el.style.setProperty('border-color', BLUE, 'important');
      el.style.setProperty('border-top-color', 'transparent', 'important');
    }

    // Case 2: Inline style spinner (from loading.tsx: style="border-top-color: #612bd3; animation: spin ...")
    if (styleAttr) {
      if (isPurple(styleAttr) || styleAttr.indexOf('spin') !== -1 || styleAttr.indexOf('border-top-color') !== -1 || styleAttr.indexOf('borderTopColor') !== -1) {
        el.style.setProperty('border-top-color', BLUE, 'important');
        if (el.style.borderRightColor && el.style.borderRightColor === 'transparent') {
          // preserve right transparent if set
        }
      }
    }

    // Case 3: Computed style check
    try {
      var computed = window.getComputedStyle(el);
      if (computed) {
        if (isPurple(computed.borderTopColor)) {
          el.style.setProperty('border-top-color', BLUE, 'important');
        }
        if (isPurple(computed.borderColor)) {
          el.style.setProperty('border-color', BLUE, 'important');
          el.style.setProperty('border-top-color', 'transparent', 'important');
        }
        if (isPurple(computed.color)) {
          el.style.setProperty('color', BLUE, 'important');
        }
      }
    } catch (e) {}
  }

  function scanDOM() {
    var all = document.body ? document.body.getElementsByTagName('*') : [];
    for (var i = 0; i < all.length; i++) {
      fixElement(all[i]);
    }
  }

  function init() {
    scanDOM();

    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (node.nodeType === 1) {
            fixElement(node);
            var children = node.getElementsByTagName('*');
            for (var k = 0; k < children.length; k++) {
              fixElement(children[k]);
            }
          }
        }
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['style', 'class']
    });

    setInterval(scanDOM, 300);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

// Google Branding Fixes
document.title = "Planna - Social Media Scheduling Application";
let metaDesc = document.querySelector('meta[name="description"]');
if (!metaDesc) {
    metaDesc = document.createElement('meta');
    metaDesc.name = "description";
    document.head.appendChild(metaDesc);
}
metaDesc.content = "Planna is a social media scheduling application that helps you plan, automate, and manage your online presence.";
