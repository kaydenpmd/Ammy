// Shared by the source page (index.html) and the app pages (app.html).
(function () {
  // source.json is served at the site's root. Change if you move it.
  var SOURCE_URL = new URL('/source.json', location.href).href;

  // Interface text, in one place. Pieces marked "sample" are the App Store's
  // own words, shown until the owner writes theirs (the wording page); the
  // rest is the old landing page's text.
  var TEXT = {
    title: "Kayden's Apps",                         // the source page's title, the owner's (26 Nov 2026)
    addSideStore: 'Add to SideStore',
    addAltStore: 'Add to AltStore',
    copy: 'Copy',
    copied: 'Copied',
    whatsNew: "What's new",
    version: function (v, build) { return 'Version ' + v + (build ? ' (build ' + build + ')' : ''); },
    information: 'Information',                     // sample
    developer: 'Developer',                         // sample
    size: 'Size',                                   // sample
    category: 'Category',                           // sample
    compatibility: 'Compatibility',                 // sample
    requires: function (v) { return 'Requires iOS ' + v + ' or later.'; },
    sha256: 'SHA-256',
    ipa: '.ipa',
    moreBy: function (who) { return 'More by ' + who; },   // sample
    notFound: 'Not found',
    notPublished: 'Nothing is published at this address.',
    toSource: '[text]',                             // the link back to the source page
    unavailable: 'Source unavailable',
    couldNotLoad: function (why) { return 'Could not load source.json (' + why + ')'; }
  };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // An app's page lives at /app/<slug>, the last part of its bundle ID.
  function slugOf(app) {
    var id = String(app.bundleIdentifier || app.name || '');
    return id.split('.').pop().toLowerCase().replace(/[^a-z0-9-]+/g, '-');
  }
  function appURL(app) { return '/app/' + encodeURIComponent(slugOf(app)); }

  // A size as its number and its unit, which the ribbon shows on two lines.
  function megabyteParts(n) {
    if (!n) return null;
    var mb = n / 1048576;
    return [mb >= 10 ? mb.toFixed(0) : mb.toFixed(1), 'MB'];
  }
  function megabytes(n) {
    var parts = megabyteParts(n);
    return parts ? parts.join(' ') : '';
  }

  // source.json's categories are lower case ("entertainment").
  function categoryName(c) {
    c = String(c || '');
    return c ? c.charAt(0).toUpperCase() + c.slice(1) : '';
  }

  function formatDate(iso) {
    return new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
  }

  function icon(url, size) {
    var box = el('div', 'icon');
    if (url) {
      var img = el('img');
      img.src = url; img.alt = ''; img.width = size; img.height = size;
      // Drawn with the page's first frame when it's already loaded, so a page
      // sliding in on a phone brings its icons with it.
      img.decoding = 'sync';
      box.appendChild(img);
    }
    return box;
  }

  // ".ipa" with a circled down arrow before it, the label of every button
  // that downloads an app (the owner, 26 Nov 2026). The arrow is a character
  // of Pretendard, the font the site serves: U+E139 (store.css sets it in that
  // font). Not an SF Symbol: Apple licenses those for apps on its own
  // platforms only.
  function ipaLabel() {
    var label = el('span');
    var symbol = el('span', 'symbol', '\uE139');
    symbol.setAttribute('aria-hidden', 'true');
    label.appendChild(symbol);
    label.appendChild(document.createTextNode(TEXT.ipa));
    return label;
  }

  // A lockup: icon, name, the subtitle or, as the App Store does for an app
  // without one, its category, and a button that downloads the app's .ipa,
  // in place of Apple's View (the owner, 26 Nov 2026: "remove the view
  // button ... actually give it an ipa button. and give it a download sf
  // symbol inside the button"), the symbol Pretendard's; an app with no .ipa
  // gets no button. The name links to the app's page, and store.css stretches that
  // link over the whole lockup, under the button, so the rest of the lockup
  // still opens the page.
  function lockup(app, small) {
    var box = el('div', 'lockup');
    box.appendChild(icon(app.iconURL, small ? 64 : 85));
    var meta = el('div', 'meta');
    var name = el('h3', 'name');
    var link = el('a', null, app.name);
    link.href = appURL(app);
    name.appendChild(link);
    meta.appendChild(name);
    var sub = app.subtitle || categoryName(app.category);
    if (sub) meta.appendChild(el('p', 'subtitle', sub));
    box.appendChild(meta);
    var v = (app.versions || [])[0] || {};
    if (v.downloadURL) {
      var button = el('a', 'get-button');
      button.appendChild(ipaLabel());
      button.href = v.downloadURL;
      if (small) box.appendChild(button); else meta.appendChild(button);
    }
    return box;
  }

  function sourceLinks(sideA, altA) {
    if (sideA) sideA.href = 'sidestore://source?url=' + SOURCE_URL;
    if (altA) altA.href = 'altstore://source?url=' + SOURCE_URL;
  }

  function copySourceURL(button) {
    var done = function () {
      button.textContent = TEXT.copied;
      setTimeout(function () { button.textContent = TEXT.copy; }, 1400);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(SOURCE_URL).then(done, done);
    } else {
      var t = document.createElement('textarea');
      t.value = SOURCE_URL;
      document.body.appendChild(t); t.select();
      try { document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(t); done();
    }
  }

  // source.json, fetched fresh each time and kept for the session, so the
  // next page can draw itself from it at once: a page that slides in on a
  // phone has to have its content in its first frame.
  var CACHE = 'store.source';
  function loadSource() {
    return fetch(SOURCE_URL, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    }).then(function (text) {
      var src = JSON.parse(text);
      try { sessionStorage.setItem(CACHE, text); } catch (e) {}
      return src;
    });
  }
  function cachedSource() {
    try { var text = sessionStorage.getItem(CACHE); return text ? JSON.parse(text) : null; } catch (e) { return null; }
  }

  // Which way a page moves on a phone (store.css, the view transition): one
  // reached by following a link on the site slides in over the page before
  // (iOS's push); any other arrival, as by going back, slides that page off
  // to uncover it (iOS's pop).
  var LINKED = 'store.linked';
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[href]');
    if (a && a.origin === location.origin) try { sessionStorage.setItem(LINKED, '1'); } catch (x) {}
  }, true);
  window.addEventListener('pagereveal', function (e) {
    var linked = false;
    try { linked = sessionStorage.getItem(LINKED) === '1'; sessionStorage.removeItem(LINKED); } catch (x) {}
    if (!e.viewTransition) return;
    var root = document.documentElement;
    root.classList.toggle('pop', !linked);
    e.viewTransition.finished.then(function () { root.classList.remove('pop'); }, function () { root.classList.remove('pop'); });
  });

  window.Store = {
    SOURCE_URL: SOURCE_URL, TEXT: TEXT, el: el, slugOf: slugOf, appURL: appURL,
    megabytes: megabytes, megabyteParts: megabyteParts, categoryName: categoryName, formatDate: formatDate,
    icon: icon, lockup: lockup, ipaLabel: ipaLabel, sourceLinks: sourceLinks, copySourceURL: copySourceURL,
    loadSource: loadSource, cachedSource: cachedSource
  };
})();
