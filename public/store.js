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
    view: 'View',                                   // sample
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
      if (size < 100) img.loading = 'lazy';
      box.appendChild(img);
    }
    return box;
  }

  // A lockup: icon, name, the subtitle or, as the App Store does for an app
  // without one, its category, and the View button. The whole lockup opens
  // the app's page. The button repeats that, but Apple has it, so it stays:
  // "if apple uses view then we'll keep it but it's still redundant lol"
  // (the owner, 20 Nov 2026).
  function lockup(app, small) {
    var a = el('a', 'lockup');
    a.href = appURL(app);
    a.appendChild(icon(app.iconURL, small ? 64 : 85));
    var meta = el('div', 'meta');
    meta.appendChild(el('h3', 'name', app.name));
    var sub = app.subtitle || categoryName(app.category);
    if (sub) meta.appendChild(el('p', 'subtitle', sub));
    var button = el('span', 'get-button', TEXT.view);
    if (small) { a.appendChild(meta); a.appendChild(button); }
    else { meta.appendChild(button); a.appendChild(meta); }
    return a;
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

  function loadSource() {
    return fetch(SOURCE_URL, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
  }

  window.Store = {
    SOURCE_URL: SOURCE_URL, TEXT: TEXT, el: el, slugOf: slugOf, appURL: appURL,
    megabytes: megabytes, megabyteParts: megabyteParts, categoryName: categoryName, formatDate: formatDate,
    icon: icon, lockup: lockup, sourceLinks: sourceLinks, copySourceURL: copySourceURL,
    loadSource: loadSource
  };
})();
