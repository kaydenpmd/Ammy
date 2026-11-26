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
      if (size < 100) img.loading = 'lazy';
      box.appendChild(img);
    }
    return box;
  }

  // A lockup: icon, name, the subtitle or, as the App Store does for an app
  // without one, its category, and a button that downloads the app's .ipa,
  // in place of Apple's View (the owner, 26 Nov 2026: "remove the view
  // button ... actually give it an ipa button. and give it a download sf
  // symbol inside the button"), the symbol Pretendard's; an app with no .ipa
  // gets no button. The name links to the app's page, and store.css stretches that
  // link over the whole lockup, under the button, so the rest of the lockup
  // still opens the page.
  // The .ipa button's symbol: the circled down arrow of Pretendard (glyph
  // U+E139 at weight 700, from fonts/PretendardStdVariable.woff2, under the
  // SIL Open Font License in fonts/), drawn from its outline, in font units
  // with y up, so phones needn't fetch the font for it. Not an SF Symbol:
  // Apple licenses those for apps on its own platforms only.
  var DOWNLOAD = 'M95 724Q95 947 205.5 1136.5Q316 1326 505 1436.5Q694 1547 917 1547Q1140 1547 1329.5 1436.5Q1519 1326 1629 1136.5Q1739 947 1739 724Q1739 501 1629 312.0Q1519 123 1329.5 12.0Q1140 -99 917 -99Q694 -99 505 12.0Q316 123 205.5 312.0Q95 501 95 724ZM1498 724Q1498 881 1420 1015.5Q1342 1150 1208 1228.0Q1074 1306 917 1306Q760 1306 626.5 1228.0Q493 1150 414 1016.0Q335 882 335 724Q335 567 414 433.5Q493 300 626.5 221.5Q760 143 917 143Q1074 143 1208 221.5Q1342 300 1420 433.5Q1498 567 1498 724ZM988 625 1157 795 1256 695 917 358 580 695 678 795 845 625 846 1086H990Z';
  function downloadSymbol() {
    var NS = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('class', 'symbol');
    svg.setAttribute('viewBox', '95 -1547 1644 1646');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var path = document.createElementNS(NS, 'path');
    path.setAttribute('transform', 'scale(1 -1)');
    path.setAttribute('d', DOWNLOAD);
    svg.appendChild(path);
    return svg;
  }

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
      var label = el('span');
      label.appendChild(downloadSymbol());
      label.appendChild(document.createTextNode(TEXT.ipa));
      button.appendChild(label);
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
