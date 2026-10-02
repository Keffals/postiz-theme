/**
 * Keffals Postiz Enhancement Script
 * Loaded via: Link: </_kg/enhance.js>; rel=modulepreload; as=script
 * 
 * HOW IT RUNS: when a <script type="module" src="/_kg/enhance.js"> tag appears
 * in the HTML (injected via the keffals-theme.css </style> trick), this file
 * executes and applies DOM enhancements.
 */
(function () {
  'use strict';
  try {
    // ── App Switcher (40px strip at top of page) ───────────────────
    var NAV_ID = 'keffals-app-switcher';
    if (!document.getElementById(NAV_ID)) {
      var strip = document.createElement('div');
      strip.id = NAV_ID;
      strip.innerHTML =
        '<a class="keffals-app-btn active" href="/">Postiz</a>' +
        '<div class="keffals-app-sep"></div>' +
        '<a class="keffals-app-btn" href="https://keffals.gg">Keffals</a>' +
        '<a class="keffals-app-btn" href="https://keffals.gg/chat">Chat</a>' +
        '<a class="keffals-app-btn" href="https://dashboard.keffals.gg">Dashboard</a>';
      document.body.prepend(strip);
    }

    // ── "Logout from Postiz" → "Sign out" ────────────────────────
    var fixLogout = function () {
      document.querySelectorAll('button,a,[role="button"],span').forEach(function (n) {
        var t = (n.textContent || '').trim();
        if (t === 'Logout from Postiz' && !n.firstChild) {
          n.textContent = 'Sign out';
        }
        if (n.title && n.title.includes('Logout from Postiz')) {
          n.title = n.title.replace('Logout from Postiz', 'Sign out');
        }
      });
    };

    // ── Set document <title> ───────────────────────────────────────
    var fixTitle = function () {
      var t = document.title || '';
      var K = ' · Keffals Postiz';
      if (t && !t.includes(K) && (t.startsWith('Postiz') || t.includes(' - Postiz'))) {
        document.title = t.replace(/^Postiz\s*-\s*/, '').replace(/\s*-\s*Postiz$/, '').trim() + K;
      }
    };

    // ── lang="en" ────────────────────────────────────────────────
    if (!document.documentElement.lang) {
      document.documentElement.lang = 'en';
    }

    // ── MutationObserver for SPA navigation ──────────────────────
    new MutationObserver(function () { fixLogout(); fixTitle(); })
      .observe(document.body, { childList: true, subtree: true });

    fixLogout();
    fixTitle();
  } catch (e) {}
})();
