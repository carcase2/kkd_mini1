class WebViewScripts {
  static String extractChapters(String seriesUrl) {
    final uri = Uri.parse(seriesUrl);
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '''
(function() {
  /*AWR_EXTRACT_CHAPTERS*/
  const base = location.origin;
  const seriesPath = '$path';
  const seenUrls = new Set();
  const seenIds = new Set();
  const chapters = [];

  function syncWait(ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) {}
  }

  const __htmlAtStart = document.documentElement.innerHTML || '';

  function collectFromHtmlRegex(html) {
    html = html || '';
    if (!html || html.indexOf('ep-row-v2-link') < 0) return;

    const linkRe = /class="ep-row-v2-link"[^>]*href="([^"]+)"|href="([^"]+)"[^>]*class="ep-row-v2-link"/g;
    var m;
    while ((m = linkRe.exec(html)) !== null) {
      const href = m[1] || m[2];
      if (!href || href.startsWith('#') || href.startsWith('javascript:')) continue;
      const fullUrl = href.startsWith('http')
        ? href
        : base + (href.startsWith('/') ? href : '/' + href);

      let urlPath;
      try { urlPath = new URL(fullUrl).pathname; } catch (e) { continue; }
      if (urlPath.endsWith('/')) urlPath = urlPath.slice(0, -1);
      if (!isChapterPath(urlPath)) continue;

      const chapterId = chapterPathId(urlPath);
      if (!chapterId || seenUrls.has(fullUrl) || seenIds.has(chapterId)) continue;

      const chunk = html.slice(m.index, m.index + 1000);
      const titleM = chunk.match(/ep-row-v2-title[\\s\\S]{0,160}?<strong>\\s*([^<]+)/i);
      const text = titleM ? titleM[1].replace(/\\s+/g, ' ').trim() : '';
      const number = parseChapterNumberFromText(text) || parseChapterNumber(fullUrl, text, false);
      if (number <= 0) continue;

      seenUrls.add(fullUrl);
      seenIds.add(chapterId);
      chapters.push({
        url: fullUrl,
        title: text && /화/.test(text) ? text : (number + '화'),
        number: number,
        publishedLabel: ''
      });
    }
  }

  function collectFromAllHtmlSources() {
    const sources = [];
    if (window.__awrCapturedHtml) sources.push(window.__awrCapturedHtml);
    if (__htmlAtStart) sources.push(__htmlAtStart);
    sources.push(document.documentElement.innerHTML || '');
    for (var i = 0; i < sources.length; i++) {
      collectFromHtmlRegex(sources[i]);
      if (chapters.length > 0) return;
    }
  }

  collectFromAllHtmlSources();
  if (chapters.length > 0) {
    // SSR HTML에 회차가 있으면 Next.js 404 치환 전에 바로 사용합니다.
  } else {
    for (var step = 0; step < 35; step++) {
      window.scrollTo(0, document.body.scrollHeight);
      syncWait(220);
    }
    window.scrollTo(0, 0);
    syncWait(350);
  }

  function isChapterPath(urlPath) {
    if (urlPath === seriesPath) return false;
    if (urlPath.startsWith(seriesPath + '/')) return true;
    if (urlPath.startsWith(seriesPath + '-')) return true;
    return false;
  }

  function chapterPathId(urlPath) {
    const parts = urlPath.split('/').filter(function(p) { return !!p; });
    return parts.length ? parts[parts.length - 1] : urlPath;
  }

  function parseChapterNumberFromText(text) {
    const compact = (text || '').replace(/\\s+/g, ' ').trim();
    const nums = [];
    var m;
    const re = /(\\d+)\\s*화/g;
    while ((m = re.exec(compact)) !== null) {
      nums.push(parseInt(m[1], 10));
    }
    if (nums.length === 1) return nums[0];

    const latest = compact.match(/최신화\\s*보기\\s*\\(?\\s*(\\d+)\\s*화/i);
    if (latest) return parseInt(latest[1], 10);
    return 0;
  }

  function isSyntheticChapterUrl(url) {
    try {
      var path = new URL(url).pathname;
      if (path.endsWith('/')) path = path.slice(0, -1);
      // Only /webtoon/{seriesId}-{n} — not real slugs like tt-Mind_Control-25
      return /^\\/webtoon\\/[^/]+-\\d+\$/.test(path);
    } catch (e) {
      return false;
    }
  }

  function parseChapterNumber(url, text, preferText) {
    if (preferText) {
      const fromTitle = parseChapterNumberFromText(text);
      if (fromTitle > 0) return fromTitle;
    }

    const urlMatch = url.match(/-(\\d+)(?:\\/)?\$/);
    if (urlMatch) return parseInt(urlMatch[1], 10);
    const slashMatch = url.match(/\\/(\\d+)(?:\\/)?\$/);
    if (slashMatch) return parseInt(slashMatch[1], 10);

    return parseChapterNumberFromText(text);
  }

  function episodeNumberFromRow(li) {
    if (!li) return 0;
    const attr = parseInt(li.getAttribute('data-episode-number') || '', 10);
    if (attr > 0) return attr;
    const titleEl = li.querySelector('.ep-row-v2-title')
      || li.querySelector('[class*="ep-row"][class*="title"]')
      || li.querySelector('[class*="title"], [class*="subject"], strong, b');
    if (!titleEl) return 0;
    return parseChapterNumberFromText(titleEl.textContent || '');
  }

  function publishedLabelFromRow(li) {
    if (!li) return '';
    const meta = li.querySelector('.ep-row-v2-meta')
      || li.querySelector('[class*="meta"], [class*="date"], time');
    if (!meta) return '';
    const text = (meta.textContent || '').replace(/\\s+/g, ' ').trim();
    const match = text.match(/(\\d{2}\\.\\d{2}\\.\\d{2})/);
    return match ? match[1] : '';
  }

  function preferChapter(existing, candidate) {
    if (!existing) return candidate;
    var picked = existing;
    if (isSyntheticChapterUrl(existing.url) && !isSyntheticChapterUrl(candidate.url)) {
      picked = candidate;
    }
    if (!picked.publishedLabel && candidate.publishedLabel) {
      picked = Object.assign({}, picked, { publishedLabel: candidate.publishedLabel });
    }
    return picked;
  }

  function linkLabel(a) {
    const row = a.closest('li.ep-row-v2') || a.closest('[class*="ep-row"]');
    const titleEl = a.querySelector('.ep-row-v2-title')
      || (row ? row.querySelector('.ep-row-v2-title') : null)
      || a.querySelector('[class*="ep-row"][class*="title"]')
      || a.querySelector('[class*="title"], [class*="subject"], [class*="name"], strong, b');
    if (titleEl) {
      return (titleEl.textContent || '').replace(/\\s+/g, ' ').trim();
    }
    const text = (a.textContent || '').replace(/\\s+/g, ' ').trim();
    const first = text.match(/(\\d+\\s*화[^\\n]{0,80})/);
    if (first) return first[1].trim();
    const latest = text.match(/최신화\\s*보기\\s*\\(?\\s*(\\d+)\\s*화/i);
    if (latest) return latest[1] + '화';
    return text.substring(0, 80);
  }

  function cleanChapterTitle(a, number) {
    const label = linkLabel(a);
    if (!label) return number + '화';
    if (/^\\d+\\s*화/.test(label)) return label;
    const subtitle = label.match(
      new RegExp('^' + number + '\\s*화\\s*[-·:]\\s*([^\\d].{1,120})\$')
    );
    if (subtitle && subtitle[1]) {
      return number + '화 - ' + subtitle[1].trim();
    }
    return number + '화 · ' + label;
  }

  function isLikelyChapterLink(a, fullUrl, options) {
    options = options || {};
    let urlPath;
    try { urlPath = new URL(fullUrl).pathname; } catch (e) { return false; }
    if (urlPath.endsWith('/')) urlPath = urlPath.slice(0, -1);
    if (!isChapterPath(urlPath)) return false;

    if (!options.allowGeneric &&
        a.classList && a.classList.contains('ep-row-v2-link')) {
      return true;
    }

    const row = a.closest('li.ep-row-v2, li.ep-row-v2--ready, li[class*="ep-row"], li[class*="episode"]');
    const episodeRoot = a.closest('#episodes, ul.ep-list-v2, ul.ep-list, .ep-list, .episode-list, .episodes, [class*="ep-list"], [class*="episode-list"]');
    if (!options.allowGeneric) {
      if (!(row && episodeRoot)) return false;
    } else if (a.closest('header, footer, nav, #comments, .comments, .related, .recommend, .hero-v2, .series-list')) {
      return false;
    }

    const text = (a.textContent || '').replace(/\\s+/g, ' ');
    if (/\\d+\\s*화/.test(text)) return true;
    if (/최신화|첫화|정주행/.test(text)) return true;
    if (row && (row.querySelector('.ep-row-v2-title') || row.querySelector('[class*="title"]'))) return true;
    if (options.allowGeneric) {
      return parseChapterNumber(fullUrl, text, true) > 0;
    }
    return chapterPathId(urlPath).length > 0;
  }

  function addChapter(fullUrl, a, li) {
    if (!fullUrl || seenUrls.has(fullUrl)) return;
    let urlPath;
    try { urlPath = new URL(fullUrl).pathname; } catch (e) { return; }
    if (urlPath.endsWith('/')) urlPath = urlPath.slice(0, -1);
    if (!isChapterPath(urlPath)) return;

    const chapterId = chapterPathId(urlPath);
    if (!chapterId || seenIds.has(chapterId)) return;

    const rawText = linkLabel(a);
    const row = li || a.closest('li.ep-row-v2, li.ep-row-v2--ready');
    const fromAttr = episodeNumberFromRow(row);
    const number = fromAttr > 0
      ? fromAttr
      : parseChapterNumber(fullUrl, rawText, true);
    if (number <= 0) return;

    const publishedLabel = publishedLabelFromRow(row);

    seenUrls.add(fullUrl);
    seenIds.add(chapterId);
    chapters.push({
      url: fullUrl,
      title: cleanChapterTitle(a, number),
      number: number,
      publishedLabel: publishedLabel
    });
  }

  function findEpisodeLink(li) {
    return li.querySelector('a.ep-row-v2-link')
      || li.querySelector('a[href*="' + seriesPath + '"]')
      || li.querySelector('a[href]');
  }

  function activateEpisodeTab() {
    const candidates = document.querySelectorAll('a, button, [role="tab"]');
    for (var i = 0; i < candidates.length; i++) {
      const t = (candidates[i].textContent || '').replace(/\\s+/g, ' ').trim();
      if (/^회차\$|^에피소드\$|^목록\$|전체\\s*회차|회차\\s*목록/i.test(t)) {
        try { candidates[i].click(); } catch (e) {}
        syncWait(500);
        return true;
      }
    }
    return false;
  }

  function collectEpListRows() {
    const rowSelector = [
      '#episodes ul.ep-list-v2 li.ep-row-v2',
      '#episodes ul.ep-list-v2 li.ep-row-v2--ready',
      'ul.ep-list-v2 li.ep-row-v2',
      'ul.ep-list-v2 li.ep-row-v2--ready',
      '#episodes ul.ep-list li',
      '#episodes .ep-list li',
      'ul.ep-list li',
      '.ep-list li',
      '.episode-list li',
      '.episodes li',
      '[class*="ep-row"]'
    ].join(', ');
    document.querySelectorAll(rowSelector).forEach(function(li) {
      const a = findEpisodeLink(li);
      if (!a) return;
      const href = a.getAttribute('href') || '';
      if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;
      const fullUrl = href.startsWith('http')
        ? href
        : base + (href.startsWith('/') ? href : '/' + href);
      if (!isLikelyChapterLink(a, fullUrl)) return;

      const rowNumber = episodeNumberFromRow(li);
      if (rowNumber > 0) {
        let urlPath;
        try { urlPath = new URL(fullUrl).pathname; } catch (e) { return; }
        if (urlPath.endsWith('/')) urlPath = urlPath.slice(0, -1);
        const chapterId = chapterPathId(urlPath);
        if (!chapterId || seenUrls.has(fullUrl) || seenIds.has(chapterId)) return;
        seenUrls.add(fullUrl);
        seenIds.add(chapterId);
        chapters.push({
          url: fullUrl,
          title: cleanChapterTitle(a, rowNumber),
          number: rowNumber,
          publishedLabel: publishedLabelFromRow(li)
        });
        return;
      }

      addChapter(fullUrl, a, li);
    });
  }

  function collectGenericChapterLinks() {
    document.querySelectorAll('a[href]').forEach(function(a) {
      const href = a.getAttribute('href') || '';
      if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;
      const fullUrl = href.startsWith('http')
        ? href
        : base + (href.startsWith('/') ? href : '/' + href);
      if (!isLikelyChapterLink(a, fullUrl, { allowGeneric: true })) return;
      addChapter(fullUrl, a, a.closest('li'));
    });
  }

  activateEpisodeTab();
  collectEpListRows();
  if (chapters.length === 0) {
    for (var retry = 0; retry < 24; retry++) {
      window.scrollTo(0, document.body.scrollHeight);
      syncWait(260);
      collectEpListRows();
      if (chapters.length > 0) break;
    }
  }
  if (chapters.length === 0) collectGenericChapterLinks();
  if (chapters.length === 0) collectFromAllHtmlSources();

  const byNumber = {};
  chapters.forEach(function(ch) {
    if (ch.number <= 0) return;
    byNumber[ch.number] = preferChapter(byNumber[ch.number], ch);
  });

  chapters.length = 0;
  Object.keys(byNumber).forEach(function(key) {
    chapters.push(byNumber[key]);
  });

  chapters.sort(function(a, b) { return a.number - b.number; });

  function normalizeCoverUrl(src) {
    if (!src || src.startsWith('data:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  }

  function isAdCoverUrl(url) {
    const lower = (url || '').toLowerCase();
    return /\\/platforms\\/|\\/brand\\/|logo-full|favicon|googletagmanager/i.test(lower);
  }

  function pickCoverUrl(url) {
    const u = normalizeCoverUrl(url);
    if (!u || isAdCoverUrl(u)) return '';
    const lower = u.toLowerCase();
    if (/logo|icon|avatar|favicon|1x1|placeholder|spinner|loading/i.test(lower)) return '';
    if (/doubleclick|googlesyndication|googleads|adsterra|adservice|\\/ads\\//i.test(lower)) return '';
    if (/webtoon_uploads/i.test(lower)) return u;
    if (/\\/thumbs?\\/|\\/black\\/thumbs\\//i.test(lower)) return u;
    if (/\\/board_uploads\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\/comics\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/lezhin\\.com\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\/(?:comic|comics|webtoon|toon|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\.(png|jpe?g|webp|gif|avif)/i.test(lower) && /thumb|cover|poster|hero|series/i.test(lower)) return u;
    return '';
  }

  function pickCoverUrlLoose(url) {
    const u = normalizeCoverUrl(url);
    if (!u || isAdCoverUrl(u)) return '';
    const lower = u.toLowerCase();
    if (/logo|icon|avatar|favicon|1x1|placeholder|spinner|loading|banner|popup|promo/i.test(lower)) return '';
    if (/doubleclick|googlesyndication|googleads|adsterra|adservice|\\/ads\\//i.test(lower)) return '';
    if (/\\/board_uploads\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (!/\\.(png|jpe?g|webp|gif|avif)(?:[?#]|\$)/i.test(lower)) return '';
    return u;
  }

  function imgCoverUrl(img, loose) {
    if (!img) return '';
    const pick = loose ? pickCoverUrlLoose : pickCoverUrl;
    const attrs = ['src', 'data-src', 'data-original', 'data-lazy-src', 'data-lazy'];
    for (var i = 0; i < attrs.length; i++) {
      const u = pick(img.getAttribute(attrs[i]) || '');
      if (u) return u;
    }
    const srcset = img.getAttribute('srcset') || '';
    if (srcset) {
      const first = srcset.split(',')[0].trim().split(/\\s+/)[0];
      const u = pick(first);
      if (u) return u;
    }
    return pick(img.currentSrc || img.src || '');
  }

  function pickPreloadCoverUrl(url) {
    const lower = (url || '').toLowerCase();
    if (isAdCoverUrl(url)) return '';
    if (/\\/board_uploads\\//i.test(lower)) return '';
    return pickCoverUrl(url);
  }

  function extractFromPreloadCover() {
    const links = document.querySelectorAll('link[rel="preload"][as="image"]');
    for (var i = 0; i < links.length; i++) {
      const href = links[i].getAttribute('href') || '';
      const u = pickPreloadCoverUrl(href);
      if (u) return u;
    }
    return '';
  }

  function extractFromHeroBg() {
    const hero = document.querySelector('.hero-v2, section.hero-v2, [class*="hero-v2"]');
    if (!hero) return '';
    const blob = (hero.getAttribute('style') || '') + ' ' + (hero.className || '') + ' ' + (hero.outerHTML || '');
    const m = blob.match(/hero-bg:url\\(([^)]+)\\)/i);
    if (!m) return '';
    return pickCoverUrl(m[1]) || pickCoverUrlLoose(m[1]);
  }

  function extractSeriesCover() {
    const og = document.querySelector(
      'meta[property="og:image"], meta[name="og:image"], meta[property="twitter:image"]'
    )?.content;
    const ogUrl = pickCoverUrl(og || '') || pickCoverUrlLoose(og || '');
    if (ogUrl) return ogUrl;

    const heroBg = extractFromHeroBg();
    if (heroBg) return heroBg;

    const preload = extractFromPreloadCover();
    if (preload) return preload;

    const heroSelectors = [
      '.hero-v2-thumb img', 'div.hero-v2-thumb img', 'section.hero-v2 img',
      '.hero-v2 img', '.hero img', '.series-hero img',
      '.vw-info img', '.vw-title img', 'main.vw-main img'
    ];
    for (var i = 0; i < heroSelectors.length; i++) {
      const u = imgCoverUrl(document.querySelector(heroSelectors[i]));
      if (u) return u;
    }

    const selectors = [
      '.series-thumb img', '.thumb img', '.poster img', '.cover img',
      '[class*="thumb"] img', '[class*="poster"] img', '[class*="cover"] img',
      'main img[alt]', 'picture img'
    ];
    for (var j = 0; j < selectors.length; j++) {
      const u = imgCoverUrl(document.querySelector(selectors[j]));
      if (u) return u;
    }

    const root = document.querySelector('section.hero-v2, .hero-v2, main.vw-main, main, #content')
      || document.body;
    var bestUrl = '';
    var bestArea = 0;
    root.querySelectorAll('img').forEach(function(img) {
      const u = imgCoverUrl(img, true);
      if (!u) return;
      const r = img.getBoundingClientRect();
      const area = Math.max(1, r.width) * Math.max(1, r.height);
      if (area > bestArea) {
        bestArea = area;
        bestUrl = u;
      }
    });
    return bestArea >= 6400 ? bestUrl : '';
  }

  function extractSeriesTitle() {
    const og = document.querySelector('meta[property="og:title"]')?.content;
    if (og) {
      const t = og.trim();
      if (t && !/^(u-)?tt-/.test(t)) return t;
    }
    const selectors = [
      'main.vw-main h1',
      '.vw-title h1',
      '.vw-info h1',
      'h1.title',
      'h1',
      '.title',
      '.post-title'
    ];
    for (var i = 0; i < selectors.length; i++) {
      const el = document.querySelector(selectors[i]);
      const t = (el?.textContent || '').replace(/\\s+/g, ' ').trim();
      if (t && t.length > 1 && !/^(u-)?tt-/.test(t) && !/^\\d+\\s*화/.test(t)) {
        return t;
      }
    }
    const docTitle = (document.title || '').split('|')[0].split('-')[0].trim();
    if (docTitle && !/^(u-)?tt-/.test(docTitle)) return docTitle;
    return '';
  }

  return JSON.stringify({
    title: extractSeriesTitle(),
    coverUrl: extractSeriesCover(),
    chapters: chapters
  });
})()
''';
  }

  static const scrollEpisodeListStep = '''
(function() {
  const targets = [
    '#episodes', 'ul.ep-list-v2', 'ul.ep-list', '.ep-list', '.episode-list', '.episodes'
  ];
  for (var i = 0; i < targets.length; i++) {
    const el = document.querySelector(targets[i]);
    if (el) {
      el.scrollTop = el.scrollHeight;
    }
  }
  window.scrollTo(0, document.body.scrollHeight);
  return {
    height: Math.max(document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0),
    y: window.scrollY,
    episodeNodes: document.querySelectorAll(
      'li.ep-row-v2, ul.ep-list li, .ep-list li, [class*="ep-row"], [class*="episode"]'
    ).length
  };
})()
''';

  /// Scroll page; use site `.vw-bot-mini` down button + collect lazy URLs.
  static const scrollCollectStep = '''
(function() {
  window.__awrCollectedUrls = window.__awrCollectedUrls || [];
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|sports.*casino|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_URL_RE = /doubleclick|googlesyndication|googleads|adsterra|exoclick|popads|propeller|juicyads|cpmstar|adnxs|taboola|outbrain|mgid|revcontent|clickadu|hilltopads|adservice|adserver|\\/ads\\/|\\/ad\\//i;

  const normalize = (src) => {
    if (!src || src.startsWith('data:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  };

  const isComicCdnUrl = (url) => {
    const lower = (url || '').toLowerCase();
    if (/\\/webtoon_uploads\\//i.test(lower)) return true;
    return /\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif)/i.test(lower);
  };

  const isBadUrl = (url) => {
    if (isComicCdnUrl(url)) return false;
    const lower = url.toLowerCase();
    return AD_URL_RE.test(lower) || GAMBLE_RE.test(lower) ||
      /\\b(banner|promo|sponsor|logo|avatar|favicon)\\b/.test(lower);
  };

  const pushUrl = (url) => {
    const u = normalize(url);
    if (!u || isBadUrl(u) || !isComicCdnUrl(u)) return;
    if (window.__awrCollectedUrls.indexOf(u) === -1) {
      window.__awrCollectedUrls.push(u);
    }
  };

  const tapVwBotMini = (which) => {
    const bar = document.querySelector('div.vw-bot-mini, .vw-bot-mini');
    if (!bar) return false;
    var nodes = bar.querySelectorAll('a, button, [onclick], [role="button"]');
    if (nodes.length === 0) nodes = bar.children;
    const list = Array.from(nodes).filter(function(el) {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
    if (list.length === 0) return false;
    const el = which === 'up' ? list[0] : list[list.length - 1];
    try {
      el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      if (typeof el.click === 'function') el.click();
      return true;
    } catch (e) {
      return false;
    }
  };

  const comicRoot = document.querySelector('div.vw-imgs')
    || document.querySelector('main.vw-main .vw-imgs')
    || document.querySelector('main.vw-main')
    || document.querySelector('.vw-imgs');

  const root = comicRoot || document.body;

  const mineHtml = (html) => {
    if (!html) return;
    const uploadRe = /https?:\\/\\/[^"'\\s<>]+\\/webtoon_uploads\\/[^"'\\s<>]+\\.(?:webp|jpe?g|png|gif)/gi;
    var m;
    while ((m = uploadRe.exec(html)) !== null) pushUrl(m[0]);
    LAZY_ATTR_RE.lastIndex = 0;
    while ((m = LAZY_ATTR_RE.exec(html)) !== null) pushUrl(m[1]);
  };

  const LAZY_ATTR_RE = /(?:data-src|data-original|data-lazy-src|data-url|data-image|data-lazy)=["']([^"']+)["']/gi;
  mineHtml(root.innerHTML || '');

  root.querySelectorAll('img').forEach((img) => {
    const attrs = ['data-src','data-original','data-lazy-src','data-url','data-lazy','data-image','src'];
    for (const a of attrs) {
      const v = img.getAttribute(a);
      if (v) pushUrl(v);
    }
    const src = img.currentSrc || img.src || '';
    if (src) pushUrl(src);
  });

  if (!window.__awrScrollStep) window.__awrScrollStep = 0;
  window.__awrScrollStep++;
  const botClicked = tapVwBotMini('down');

  const stepPx = 900;
  const maxY = Math.max((document.body.scrollHeight || 0) - 1, 0);
  const nextY = Math.min((window.scrollY || 0) + stepPx, maxY);
  window.scrollTo(0, nextY);
  if (comicRoot) {
    try { comicRoot.scrollTop = Math.min(comicRoot.scrollTop + stepPx, comicRoot.scrollHeight); } catch (e) {}
  }
  return JSON.stringify({
    height: document.body.scrollHeight || 0,
    y: window.scrollY || 0,
    collected: window.__awrCollectedUrls.length,
    botClicked: botClicked
  });
})()
''';

  /// Jump to chapter bottom via site floating controls (vw-bot-mini ↓).
  static const scrollToBottomViaSiteButton = '''
(function() {
  const bar = document.querySelector('div.vw-bot-mini, .vw-bot-mini');
  if (!bar) return JSON.stringify({ ok: false, reason: 'no-bar' });
  var nodes = bar.querySelectorAll('a, button, [onclick], [role="button"]');
  if (nodes.length === 0) nodes = bar.children;
  const list = Array.from(nodes).filter(function(el) {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  });
  if (list.length === 0) return JSON.stringify({ ok: false, reason: 'no-buttons' });
  const down = list[list.length - 1];
  try {
    down.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    if (typeof down.click === 'function') down.click();
    return JSON.stringify({ ok: true, buttons: list.length });
  } catch (e) {
    return JSON.stringify({ ok: false, reason: String(e) });
  }
})()
''';

  /// Mine visible comic images and read vw-bot-mini page indicator (one pager step).
  static const pagerCollectStep = '''
(function() {
  window.__awrCollectedUrls = window.__awrCollectedUrls || [];
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|sports.*casino|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_URL_RE = /doubleclick|googlesyndication|googleads|adsterra|exoclick|popads|propeller|juicyads|cpmstar|adnxs|taboola|outbrain|mgid|revcontent|clickadu|hilltopads|adservice|adserver|\\/ads\\/|\\/ad\\//i;

  const normalize = (src) => {
    if (!src || src.startsWith('data:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  };

  const isComicCdnUrl = (url) => {
    const lower = (url || '').toLowerCase();
    if (/\\/webtoon_uploads\\//i.test(lower)) return true;
    return /\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif)/i.test(lower);
  };

  const isBadUrl = (url) => {
    if (isComicCdnUrl(url)) return false;
    const lower = url.toLowerCase();
    return AD_URL_RE.test(lower) || GAMBLE_RE.test(lower) ||
      /\\b(banner|promo|sponsor|logo|avatar|favicon)\\b/.test(lower);
  };

  const pushUrl = (url) => {
    const u = normalize(url);
    if (!u || isBadUrl(u) || !isComicCdnUrl(u)) return;
    if (window.__awrCollectedUrls.indexOf(u) === -1) {
      window.__awrCollectedUrls.push(u);
    }
  };

  const mineVisible = () => {
    const root = document.querySelector('div.vw-imgs')
      || document.querySelector('main.vw-main .vw-imgs')
      || document.querySelector('main.vw-main')
      || document.querySelector('.vw-imgs')
      || document.body;
    const html = root.innerHTML || '';
    const uploadRe = /https?:\\/\\/[^"'\\s<>]+\\/webtoon_uploads\\/[^"'\\s<>]+\\.(?:webp|jpe?g|png|gif)/gi;
    var m;
    while ((m = uploadRe.exec(html)) !== null) pushUrl(m[0]);
    root.querySelectorAll('img').forEach(function(img) {
      const attrs = ['data-src','data-original','data-lazy-src','data-url','data-lazy','data-image','src'];
      for (var i = 0; i < attrs.length; i++) {
        const v = img.getAttribute(attrs[i]);
        if (v) pushUrl(v);
      }
      const src = img.currentSrc || img.src || '';
      if (src) pushUrl(src);
    });
  };

  mineVisible();

  const text = (document.querySelector('div.vw-bot-mini') || document.querySelector('.vw-bot-mini') || {}).textContent || '';
  const m = text.match(/(\\d+)\\s*\\/\\s*(\\d+)/);
  const current = m ? parseInt(m[1], 10) : 0;
  const total = m ? parseInt(m[2], 10) : 0;

  return JSON.stringify({
    collected: window.__awrCollectedUrls.length,
    current: current,
    total: total
  });
})()
''';

  static const pagerClickUp = '''
(function() {
  const bar = document.querySelector('div.vw-bot-mini, .vw-bot-mini');
  if (!bar) return JSON.stringify({ clicked: false });
  var nodes = bar.querySelectorAll('a, button, [onclick], [role="button"]');
  if (nodes.length === 0) nodes = bar.children;
  const list = Array.from(nodes).filter(function(el) {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  });
  if (list.length === 0) return JSON.stringify({ clicked: false });
  const up = list[0];
  try {
    up.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    if (typeof up.click === 'function') up.click();
    return JSON.stringify({ clicked: true });
  } catch (e) {
    return JSON.stringify({ clicked: false });
  }
})()
''';

  static const pagerClickDown = '''
(function() {
  const bar = document.querySelector('div.vw-bot-mini, .vw-bot-mini');
  if (!bar) return JSON.stringify({ clicked: false });
  var nodes = bar.querySelectorAll('a, button, [onclick], [role="button"]');
  if (nodes.length === 0) nodes = bar.children;
  const list = Array.from(nodes).filter(function(el) {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  });
  if (list.length === 0) return JSON.stringify({ clicked: false });
  const down = list[list.length - 1];
  try {
    down.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    if (typeof down.click === 'function') down.click();
    return JSON.stringify({ clicked: true });
  } catch (e) {
    return JSON.stringify({ clicked: false });
  }
})()
''';

  /// Page-by-page viewer: click vw-bot-mini ↓ until last page, collect each image URL.
  static const pagerCollectAllImages = '''
(function() {
  window.__awrCollectedUrls = window.__awrCollectedUrls || [];
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|sports.*casino|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_URL_RE = /doubleclick|googlesyndication|googleads|adsterra|exoclick|popads|propeller|juicyads|cpmstar|adnxs|taboola|outbrain|mgid|revcontent|clickadu|hilltopads|adservice|adserver|\\/ads\\/|\\/ad\\//i;

  const normalize = (src) => {
    if (!src || src.startsWith('data:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  };

  const isComicCdnUrl = (url) => {
    const lower = (url || '').toLowerCase();
    if (/\\/webtoon_uploads\\//i.test(lower)) return true;
    return /\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif)/i.test(lower);
  };

  const isBadUrl = (url) => {
    if (isComicCdnUrl(url)) return false;
    const lower = url.toLowerCase();
    return AD_URL_RE.test(lower) || GAMBLE_RE.test(lower) ||
      /\\b(banner|promo|sponsor|logo|avatar|favicon)\\b/.test(lower);
  };

  const pushUrl = (url) => {
    const u = normalize(url);
    if (!u || isBadUrl(u) || !isComicCdnUrl(u)) return;
    if (window.__awrCollectedUrls.indexOf(u) === -1) {
      window.__awrCollectedUrls.push(u);
    }
  };

  const tapVwBotMini = (which) => {
    const bar = document.querySelector('div.vw-bot-mini, .vw-bot-mini');
    if (!bar) return false;
    var nodes = bar.querySelectorAll('a, button, [onclick], [role="button"]');
    if (nodes.length === 0) nodes = bar.children;
    const list = Array.from(nodes).filter(function(el) {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });
    if (list.length === 0) return false;
    const el = which === 'up' ? list[0] : list[list.length - 1];
    try {
      el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      if (typeof el.click === 'function') el.click();
      return true;
    } catch (e) {
      return false;
    }
  };

  const syncWait = (ms) => {
    const end = Date.now() + ms;
    while (Date.now() < end) {}
  };

  const mineVisible = () => {
    const root = document.querySelector('div.vw-imgs')
      || document.querySelector('main.vw-main .vw-imgs')
      || document.querySelector('main.vw-main')
      || document.querySelector('.vw-imgs')
      || document.body;
    const html = root.innerHTML || '';
    const uploadRe = /https?:\\/\\/[^"'\\s<>]+\\/webtoon_uploads\\/[^"'\\s<>]+\\.(?:webp|jpe?g|png|gif)/gi;
    var m;
    while ((m = uploadRe.exec(html)) !== null) pushUrl(m[0]);
    root.querySelectorAll('img').forEach(function(img) {
      const attrs = ['data-src','data-original','data-lazy-src','data-url','data-lazy','data-image','src'];
      for (var i = 0; i < attrs.length; i++) {
        const v = img.getAttribute(attrs[i]);
        if (v) pushUrl(v);
      }
      const src = img.currentSrc || img.src || '';
      if (src) pushUrl(src);
    });
  };

  const readState = () => {
    const text = (document.querySelector('div.vw-bot-mini') || document.querySelector('.vw-bot-mini') || {}).textContent || '';
    const m = text.match(/(\\d+)\\s*\\/\\s*(\\d+)/);
    if (m) return { current: parseInt(m[1], 10), total: parseInt(m[2], 10) };
    return { current: 0, total: 0 };
  };

  for (var up = 0; up < 8; up++) {
    if (!tapVwBotMini('up')) break;
    syncWait(180);
  }
  mineVisible();

  var state = readState();
  var total = state.total;
  var lastCurrent = -1;
  var stale = 0;

  for (var i = 0; i < 400; i++) {
    mineVisible();
    state = readState();
    if (state.total > 0) total = state.total;

    if (total > 0 && window.__awrCollectedUrls.length >= total) break;
    if (total > 0 && state.current >= state.total) {
      mineVisible();
      syncWait(1200);
      mineVisible();
      break;
    }

    if (!tapVwBotMini('down')) {
      window.scrollTo(0, (window.scrollY || 0) + 800);
    }
    syncWait(650);

    if (state.current === lastCurrent) {
      stale++;
    } else {
      stale = 0;
    }
    lastCurrent = state.current;

    if (stale > 40) break;
  }

  mineVisible();
  syncWait(800);
  mineVisible();
  state = readState();
  return JSON.stringify({
    collected: window.__awrCollectedUrls.length,
    current: state.current,
    total: state.total
  });
})()
''';

  static const extractImages = '''
(function() {
  /*AWR_EXTRACT_IMAGES*/
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|sports.*casino|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_URL_RE = /doubleclick|googlesyndication|googleads|adsterra|exoclick|popads|propeller|juicyads|cpmstar|adnxs|taboola|outbrain|mgid|revcontent|clickadu|hilltopads|adservice|adserver|creativecdn|\\/ads\\/|\\/ad\\//i;
  const AD_PARENT_RE = /\\b(ad|ads|advert|banner|sponsor|popup|promo|sidebar|widget|teaser|native-ad)\\b/i;
  const LAZY_ATTR_RE = /(?:data-src|data-original|data-lazy-src|data-url|data-image|data-lazy)=["']([^"']+)["']/gi;
  const COMIC_CONTAINER_SELECTORS = [
    'div.vw-imgs', 'main.vw-main .vw-imgs', 'main.vw-main', '.vw-imgs',
    '#readerarea', '.reading-content', '.viewer', '#viewer', '.webtoon-viewer',
    '#toon_content', '.wt_viewer', '.view_content', '.comic_view', 'article.episode',
    '#comic', '#content .viewer', '.episode-content', '.toon_viewer'
  ];

  function normalizeUrl(src) {
    if (!src || src.startsWith('data:') || src.startsWith('blob:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  }

  function isComicCdnUrl(url) {
    const lower = (url || '').toLowerCase();
    if (/\\/webtoon_uploads\\//i.test(lower)) return true;
    return /\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif)/i.test(lower);
  }

  function isBadUrl(url) {
    if (isComicCdnUrl(url)) return false;
    const lower = url.toLowerCase();
    if (AD_URL_RE.test(lower) || GAMBLE_RE.test(lower)) return true;
    if (lower.includes('logo') || lower.includes('avatar') || lower.includes('favicon')) return true;
    if (/\\b(banner|promo|sponsor)\\b/.test(lower)) return true;
    if (/placeholder|loading|1x1|blank|spinner/.test(lower)) return true;
    return false;
  }

  function imgUrl(img) {
    const attrs = ['data-src','data-original','data-lazy-src','data-url','data-lazy','data-image'];
    for (var i = 0; i < attrs.length; i++) {
      const v = img.getAttribute(attrs[i]);
      if (v) return normalizeUrl(v);
    }
    return normalizeUrl(img.currentSrc || img.src || '');
  }

  function pageNumFromAlt(alt) {
    const m = (alt || '').match(/page\\s*(\\d+)/i);
    return m ? parseInt(m[1], 10) : 0;
  }

  function findComicContainer() {
    for (var i = 0; i < COMIC_CONTAINER_SELECTORS.length; i++) {
      const el = document.querySelector(COMIC_CONTAINER_SELECTORS[i]);
      if (!el) continue;
      const html = el.innerHTML || '';
      if (el.querySelectorAll('img').length > 0 || isComicCdnUrl(html) || /webtoon_uploads/i.test(html)) {
        return el;
      }
    }
    return null;
  }

  function collectImgTagsFromHtml() {
    const container = findComicContainer();
    if (!container) return [];
    const html = container.innerHTML || '';
    const items = [];
    const seen = new Set();
    var order = 0;
    const tagRe = /<img\\b[^>]*>/gi;
    var tag;
    while ((tag = tagRe.exec(html)) !== null) {
      const chunk = tag[0];
      var url = '';
      const lazyM = chunk.match(
        /(?:data-src|data-original|data-lazy-src|data-url|data-lazy)=["']([^"']+)["']/i
      );
      if (lazyM) url = normalizeUrl(lazyM[1]);
      if (!url) {
        const srcM = chunk.match(/\\bsrc=["']([^"']+)["']/i);
        if (srcM) url = normalizeUrl(srcM[1]);
      }
      if (!url || seen.has(url) || isBadUrl(url)) continue;
      seen.add(url);
      const altM = chunk.match(/\\balt=["']([^"']+)["']/i);
      const pageNum = pageNumFromAlt(altM ? altM[1] : '') || order + 1;
      items.push({ url: url, pageNum: pageNum, htmlOrder: order++, top: 0 });
    }
    return items;
  }

  function collectUploadUrlsFromHtml() {
    const container = findComicContainer();
    if (!container) return [];
    const html = container.innerHTML || '';
    const items = [];
    const seen = new Set();
    var order = 0;
    const uploadRe = /https?:\\/\\/[^"'\\s<>]+\\/webtoon_uploads\\/[^"'\\s<>]+\\.(?:webp|jpe?g|png|gif)/gi;
    var m;
    while ((m = uploadRe.exec(html)) !== null) {
      const url = normalizeUrl(m[0]);
      if (!url || seen.has(url) || isBadUrl(url)) continue;
      seen.add(url);
      items.push({ url: url, pageNum: order + 1, htmlOrder: order++, top: 0 });
    }
    return items;
  }

  function collectUploadUrlsFromDocument() {
    const html = document.documentElement ? document.documentElement.outerHTML : '';
    const items = [];
    const seen = new Set();
    var order = 0;
    const uploadRe = /https?:\\/\\/[^"'\\s<>]+\\/webtoon_uploads\\/[^"'\\s<>]+\\.(?:webp|jpe?g|png|gif)/gi;
    var m;
    while ((m = uploadRe.exec(html)) !== null) {
      const url = normalizeUrl(m[0]);
      if (!url || seen.has(url) || isBadUrl(url)) continue;
      seen.add(url);
      items.push({ url: url, pageNum: order + 1, htmlOrder: order++, top: 0 });
    }
    return items;
  }

  function collectFromComicContainer() {
    const container = findComicContainer();
    if (!container) return [];

    const items = [];
    const seen = new Set();
    container.querySelectorAll('img').forEach(function(img, idx) {
      const url = imgUrl(img);
      if (!url || seen.has(url) || isBadUrl(url)) return;
      seen.add(url);
      const r = img.getBoundingClientRect();
      const alt = img.getAttribute('alt') || '';
      items.push({
        url: url,
        top: r.top + (window.scrollY || 0),
        pageNum: pageNumFromAlt(alt) || idx + 1,
        htmlOrder: idx
      });
    });

    items.sort(function(a, b) {
      if (a.pageNum !== b.pageNum) return a.pageNum - b.pageNum;
      return a.top - b.top;
    });
    return items;
  }

  function collectLazyFromContainer() {
    const container = findComicContainer();
    if (!container) return [];
    const html = container.innerHTML || '';
    const items = [];
    const seen = new Set();
    var order = 0;
    var m;
    LAZY_ATTR_RE.lastIndex = 0;
    while ((m = LAZY_ATTR_RE.exec(html)) !== null) {
      const url = normalizeUrl(m[1]);
      if (!url || seen.has(url) || isBadUrl(url)) continue;
      seen.add(url);
      items.push({ url: url, pageNum: order + 1, htmlOrder: order++, top: 0 });
    }
    return items;
  }

  function mergeItems(primary, extra) {
    const seen = new Set(primary.map(function(i) { return i.url; }));
    const merged = primary.slice();
    extra.forEach(function(item) {
      if (!seen.has(item.url)) {
        seen.add(item.url);
        merged.push(item);
      }
    });
    merged.sort(function(a, b) {
      if (a.pageNum !== b.pageNum) return a.pageNum - b.pageNum;
      if (a.top > 0 && b.top > 0) return a.top - b.top;
      return (a.htmlOrder || 0) - (b.htmlOrder || 0);
    });
    return merged;
  }

  function extractNow() {
    const collected = Array.isArray(window.__awrCollectedUrls) ? window.__awrCollectedUrls : [];
    const pagerUrls = [];
    const pagerSeen = new Set();
    collected.forEach(function(u) {
      const url = normalizeUrl(u);
      if (!url || isBadUrl(url) || !isComicCdnUrl(url) || pagerSeen.has(url)) return;
      pagerSeen.add(url);
      pagerUrls.push(url);
    });

    const total = detectPageTotal();
    if (pagerUrls.length >= 3) {
      if (total <= 0 || pagerUrls.length >= total) return pagerUrls;
    }

    var items = collectFromComicContainer();
    items = mergeItems(items, collectImgTagsFromHtml());
    items = mergeItems(items, collectLazyFromContainer());
    items = mergeItems(items, collectUploadUrlsFromHtml());

    const domUrls = [];
    const seenUrls = new Set();
    items.forEach(function(item) {
      if (!item.url || seenUrls.has(item.url)) return;
      seenUrls.add(item.url);
      domUrls.push(item.url);
    });

    if (pagerUrls.length >= domUrls.length) return pagerUrls;

    pagerUrls.forEach(function(url) {
      if (!seenUrls.has(url)) {
        seenUrls.add(url);
        domUrls.push(url);
      }
    });
    return domUrls;
  }

  function detectPageTotal() {
    const sources = [
      document.querySelector('div.vw-bot-mini')?.textContent || '',
      document.querySelector('.vw-bot-mini')?.textContent || '',
      document.querySelector('.vw-bot')?.textContent || '',
      document.querySelector('h1')?.textContent || '',
      document.querySelector('.chapter-title')?.textContent || '',
      document.title || '',
      (document.body?.innerText || '').substring(0, 3000)
    ];
    for (var s = 0; s < sources.length; s++) {
      const m = sources[s].match(/(\\d+)\\s*\\/\\s*(\\d+)/);
      if (m) {
        const total = parseInt(m[2], 10);
        if (total > 0 && total <= 500) return total;
      }
    }
    const collected = Array.isArray(window.__awrCollectedUrls)
      ? window.__awrCollectedUrls.length
      : 0;
    const container = findComicContainer();
    const imgCount = container ? container.querySelectorAll('img').length : 0;
    return Math.max(collected, imgCount);
  }

  return JSON.stringify({ urls: extractNow(), pageTotal: detectPageTotal() });
})()
''';

  /// Reads total page count shown on chapter viewer (e.g. "1 / 50").
  static const detectPageTotal = '''
(function() {
  const sources = [
    document.querySelector('div.vw-bot-mini')?.textContent || '',
    document.querySelector('.vw-bot-mini')?.textContent || '',
    document.querySelector('.vw-bot')?.textContent || '',
    document.querySelector('h1')?.textContent || '',
    document.querySelector('.chapter-title')?.textContent || '',
    document.title || '',
    (document.body?.innerText || '').substring(0, 3000)
  ];
  for (var i = 0; i < sources.length; i++) {
    const m = sources[i].match(/(\\d+)\\s*\\/\\s*(\\d+)/);
    if (m) {
      const total = parseInt(m[2], 10);
      if (total > 0 && total <= 500) {
        return JSON.stringify({ pageTotal: total });
      }
    }
  }
  const collected = Array.isArray(window.__awrCollectedUrls)
    ? window.__awrCollectedUrls.length
    : 0;
  const container = document.querySelector('div.vw-imgs')
    || document.querySelector('main.vw-main .vw-imgs')
    || document.querySelector('main.vw-main');
  const imgCount = container ? container.querySelectorAll('img').length : 0;
  const fallback = Math.max(collected, imgCount);
  return JSON.stringify({ pageTotal: fallback > 0 ? fallback : 0 });
})()
''';

  static const blockContextMenu = '''
(function() {
  const block = function(e) { e.preventDefault(); return false; };
  document.addEventListener('contextmenu', block, true);
  document.addEventListener('dragstart', block, true);
})();
''';

  static const extractTitle = '''
(function() {
  /*AWR_EXTRACT_TITLE*/
  function normalizeCoverUrl(src) {
    if (!src || src.startsWith('data:')) return '';
    if (src.startsWith('//')) return location.protocol + src;
    if (src.startsWith('http')) return src;
    return location.origin + (src.startsWith('/') ? src : '/' + src);
  }

  function isAdCoverUrl(url) {
    const lower = (url || '').toLowerCase();
    return /\\/platforms\\/|\\/brand\\/|logo-full|favicon|googletagmanager/i.test(lower);
  }

  function pickCoverUrl(url) {
    const u = normalizeCoverUrl(url);
    if (!u || isAdCoverUrl(u)) return '';
    const lower = u.toLowerCase();
    if (/logo|icon|avatar|favicon|1x1|placeholder|spinner|loading/i.test(lower)) return '';
    if (/doubleclick|googlesyndication|googleads|adsterra|adservice|\\/ads\\//i.test(lower)) return '';
    if (/webtoon_uploads/i.test(lower)) return u;
    if (/\\/thumbs?\\/|\\/black\\/thumbs\\//i.test(lower)) return u;
    if (/\\/board_uploads\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\/comics\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/lezhin\\.com\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\/(?:comic|comics|webtoon|toon|uploads?|data|img)\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (/\\.(png|jpe?g|webp|gif|avif)/i.test(lower) && /thumb|cover|poster|hero|series/i.test(lower)) return u;
    return '';
  }

  function pickCoverUrlLoose(url) {
    const u = normalizeCoverUrl(url);
    if (!u || isAdCoverUrl(u)) return '';
    const lower = u.toLowerCase();
    if (/logo|icon|avatar|favicon|1x1|placeholder|spinner|loading|banner|popup|promo/i.test(lower)) return '';
    if (/doubleclick|googlesyndication|googleads|adsterra|adservice|\\/ads\\//i.test(lower)) return '';
    if (/\\/board_uploads\\/[^?#]+\\.(?:webp|jpe?g|png|gif|avif)/i.test(lower)) return u;
    if (!/\\.(png|jpe?g|webp|gif|avif)(?:[?#]|\$)/i.test(lower)) return '';
    return u;
  }

  function imgCoverUrl(img, loose) {
    if (!img) return '';
    const pick = loose ? pickCoverUrlLoose : pickCoverUrl;
    const attrs = ['src', 'data-src', 'data-original', 'data-lazy-src', 'data-lazy'];
    for (var i = 0; i < attrs.length; i++) {
      const u = pick(img.getAttribute(attrs[i]) || '');
      if (u) return u;
    }
    const srcset = img.getAttribute('srcset') || '';
    if (srcset) {
      const first = srcset.split(',')[0].trim().split(/\\s+/)[0];
      const u = pick(first);
      if (u) return u;
    }
    return pick(img.currentSrc || img.src || '');
  }

  function pickPreloadCoverUrl(url) {
    const lower = (url || '').toLowerCase();
    if (isAdCoverUrl(url)) return '';
    if (/\\/board_uploads\\//i.test(lower)) return '';
    return pickCoverUrl(url);
  }

  function extractFromPreloadCover() {
    const links = document.querySelectorAll('link[rel="preload"][as="image"]');
    for (var i = 0; i < links.length; i++) {
      const href = links[i].getAttribute('href') || '';
      const u = pickPreloadCoverUrl(href);
      if (u) return u;
    }
    return '';
  }

  function extractFromHeroBg() {
    const hero = document.querySelector('.hero-v2, section.hero-v2, [class*="hero-v2"]');
    if (!hero) return '';
    const blob = (hero.getAttribute('style') || '') + ' ' + (hero.className || '') + ' ' + (hero.outerHTML || '');
    const m = blob.match(/hero-bg:url\\(([^)]+)\\)/i);
    if (!m) return '';
    return pickCoverUrl(m[1]) || pickCoverUrlLoose(m[1]);
  }

  function extractSeriesCover() {
    const og = document.querySelector(
      'meta[property="og:image"], meta[name="og:image"], meta[property="twitter:image"]'
    )?.content;
    const ogUrl = pickCoverUrl(og || '') || pickCoverUrlLoose(og || '');
    if (ogUrl) return ogUrl;

    const heroBg = extractFromHeroBg();
    if (heroBg) return heroBg;

    const preload = extractFromPreloadCover();
    if (preload) return preload;

    const heroSelectors = [
      '.hero-v2-thumb img', 'div.hero-v2-thumb img', 'section.hero-v2 img',
      '.hero-v2 img', '.hero img', '.series-hero img',
      '.vw-info img', '.vw-title img', 'main.vw-main img'
    ];
    for (var i = 0; i < heroSelectors.length; i++) {
      const u = imgCoverUrl(document.querySelector(heroSelectors[i]));
      if (u) return u;
    }

    const selectors = [
      '.series-thumb img', '.thumb img', '.poster img', '.cover img',
      '[class*="thumb"] img', '[class*="poster"] img', '[class*="cover"] img',
      'main img[alt]', 'picture img'
    ];
    for (var j = 0; j < selectors.length; j++) {
      const u = imgCoverUrl(document.querySelector(selectors[j]));
      if (u) return u;
    }

    const root = document.querySelector('section.hero-v2, .hero-v2, main.vw-main, main, #content')
      || document.body;
    var bestUrl = '';
    var bestArea = 0;
    root.querySelectorAll('img').forEach(function(img) {
      const u = imgCoverUrl(img, true);
      if (!u) return;
      const r = img.getBoundingClientRect();
      const area = Math.max(1, r.width) * Math.max(1, r.height);
      if (area > bestArea) {
        bestArea = area;
        bestUrl = u;
      }
    });
    return bestArea >= 6400 ? bestUrl : '';
  }

  const og = document.querySelector('meta[property="og:title"]')?.content;
  var title = '';
  if (og) {
    const t = og.trim();
    if (t && !/^(u-)?tt-/.test(t)) title = t;
  }
  if (!title) {
    const selectors = [
      'main.vw-main h1',
      '.vw-title h1',
      '.vw-info h1',
      'h1.title',
      'h1',
      '.title',
      '.post-title'
    ];
    for (var i = 0; i < selectors.length; i++) {
      const el = document.querySelector(selectors[i]);
      const t = (el?.textContent || '').replace(/\\s+/g, ' ').trim();
      if (t && t.length > 1 && !/^(u-)?tt-/.test(t) && !/^\\d+\\s*화/.test(t)) {
        title = t;
        break;
      }
    }
  }
  if (!title) {
    const docTitle = (document.title || '').split('|')[0].split('-')[0].trim();
    title = docTitle && !/^(u-)?tt-/.test(docTitle)
      ? docTitle
      : location.pathname.split('/').pop();
  }
  return JSON.stringify({ title: title, coverUrl: extractSeriesCover() });
})()
''';

  /// Hide site chrome/ads and show only the comic viewer area.
  static const readerLazyLoadScroll = '''
(function() {
  const max = Math.max(
    document.body.scrollHeight || 0,
    document.documentElement.scrollHeight || 0
  ) - window.innerHeight;
  const step = Math.max(window.innerHeight * 0.85, 480);
  const next = Math.min(window.scrollY + step, Math.max(0, max));
  window.scrollTo(0, next);
  return { y: next, max: max, done: next >= max - 12 };
})()
''';

  static const measureReaderContent = '''
(function() {
  const COMIC_SELECTORS = [
    'div.vw-imgs', 'main.vw-main .vw-imgs', 'main.vw-main', '.vw-imgs',
    '#readerarea', '.reading-content', '.viewer', '#viewer', '.webtoon-viewer',
    '#toon_content', '.wt_viewer', '.view_content', '.comic_view', 'article.episode',
    '#comic', '#content .viewer', '.episode-content', '.toon_viewer'
  ];
  // 사이트 광고 슬롯(ad-guard가 검증하는 배너)입니다. 본문 이미지로 세지 않습니다.
  const AD_SLOT_SEL = '[data-br], [data-bs], [data-bp], [data-brs]';
  const AD_IMG_RE = /board_uploads|\\/banners?\\//i;

  function isAdSlotImg(img) {
    if (!img) return false;
    if (img.closest && img.closest(AD_SLOT_SEL)) return true;
    return AD_IMG_RE.test(img.currentSrc || img.getAttribute('src') || '');
  }

  function hasNonAdImg(el) {
    const imgs = el.querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) {
      if (!isAdSlotImg(imgs[i])) return true;
    }
    return false;
  }

  function findComicContainer() {
    for (var i = 0; i < COMIC_SELECTORS.length; i++) {
      const el = document.querySelector(COMIC_SELECTORS[i]);
      if (!el) continue;
      if (hasNonAdImg(el)) return el;
      if (/webtoon_uploads|\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\//i.test(el.innerHTML || '')) {
        return el;
      }
    }
    return null;
  }

  // 광고 배너는 넓은 화면에서 100px를 넘기 때문에 본문 이미지로 세면
  // 광고 검증(ad-ack)이 끝나기 전에 읽기 모드가 켜져 403이 납니다.
  function visibleImgCount(comic) {
    var count = 0;
    const root = comic || document;
    root.querySelectorAll('img').forEach(function(img) {
      if (isAdSlotImg(img)) return;
      const r = img.getBoundingClientRect();
      if (r.width < 100 || r.height < 100) return;
      const st = window.getComputedStyle(img);
      if (st.display === 'none' || st.visibility === 'hidden') return;
      if (parseFloat(st.opacity || '1') < 0.05) return;
      count++;
    });
    return count;
  }

  function isAdVerificationGate() {
    const blob = ((document.documentElement && document.documentElement.innerHTML) || '')
      + ' ' + ((document.body && document.body.innerText) || '');
    return /ad_ack_required|webtoon-images:initial-ack|광고 검증이 완료되지 않았습니다|광고 검증 요청을 차단/i.test(blob);
  }

  const comic = findComicContainer();
  return {
    visibleImages: visibleImgCount(comic),
    comicFound: !!comic,
    adAckReady: !!window.__ntk_ad_ack_scope,
    adVerificationBlocked: isAdVerificationGate(),
    scrollHeight: Math.max(document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0),
    readerMode: document.body.classList.contains('awr-reader-mode')
  };
})()
''';

  /// 광고 검증 실패 화면의 [다시 시도]를 누릅니다.
  static const clickAdVerificationRetry = '''
(function() {
  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 8 || r.height < 8) return false;
    const st = window.getComputedStyle(el);
    return st.display !== 'none' && st.visibility !== 'hidden';
  }
  const nodes = document.querySelectorAll('button, a, [role="button"], input[type="button"]');
  for (var i = 0; i < nodes.length; i++) {
    const el = nodes[i];
    const t = ((el.textContent || el.value || '') + '').replace(/\\s+/g, ' ').trim();
    if (!/^(다시\\s*시도|재시도|Retry|Try again)\$/i.test(t)) continue;
    if (!isVisible(el)) continue;
    try {
      el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
      if (typeof el.click === 'function') el.click();
      return true;
    } catch (e) {}
  }
  return false;
})()
''';

  static const disableReaderMode = '''
(function() {
  document.documentElement.classList.remove('awr-reader-mode');
  document.body.classList.remove('awr-reader-mode');

  const style = document.getElementById('awr-reader-style');
  if (style) style.textContent = '';

  const early = document.getElementById('awr-reader-early');
  if (early) early.remove();

  document.querySelectorAll('[data-awr-hidden]').forEach(function(el) {
    const prev = el.getAttribute('data-awr-prev-style');
    if (prev == null) el.removeAttribute('style');
    else el.setAttribute('style', prev);
    el.removeAttribute('data-awr-hidden');
    el.removeAttribute('data-awr-prev-style');
  });

  if (window.__awrReaderObserver) {
    window.__awrReaderObserver.disconnect();
    window.__awrReaderObserver = null;
  }
  window.__awrReaderApply = false;
  window.__awrComicRoot = null;
  window.__awrReaderJumpedToComic = false;

  document.documentElement.style.removeProperty('overflow-y');
  document.body.style.removeProperty('overflow-y');

  return true;
})()
''';

  static const applyReaderMode = '''
(function() {
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|sports.*casino|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_URL_RE = /doubleclick|googlesyndication|googleads|adsterra|exoclick|popads|propeller|juicyads|cpmstar|adnxs|taboola|outbrain|mgid|revcontent|clickadu|hilltopads|adservice|adserver|creativecdn|\\/ads\\/|\\/ad\\//i;
  const COMIC_SEL = 'div.vw-imgs, .vw-imgs, main.vw-main, #readerarea, .reading-content, .viewer, #viewer, .webtoon-viewer, #toon_content, .wt_viewer, .view_content, .comic_view, article.episode, #comic, .episode-content, .toon_viewer';
  const COMIC_CONTAINER_SELECTORS = [
    'div.vw-imgs', 'main.vw-main .vw-imgs', 'main.vw-main', '.vw-imgs',
    '#readerarea', '.reading-content', '.viewer', '#viewer', '.webtoon-viewer',
    '#toon_content', '.wt_viewer', '.view_content', '.comic_view', 'article.episode',
    '#comic', '#content .viewer', '.episode-content', '.toon_viewer'
  ];
  const PAGER_SEL = '.vw-bot-mini, .vw-bot, div.vw-bot-mini';
  const HEADER_AD_SEL = [
    'main.vw-main > section[data-brs="header"]',
    'main.vw-main > section[data-br-n]',
    'section[data-brs="header"]',
    'section[data-br="1"]',
    '[data-brs="header"]'
  ].join(',');
  const CHROME_SEL = [
    'header', 'footer', 'nav', 'aside',
    '.header', '.footer', '.navbar', '.sidebar',
    '.vw-top', '.vw-info', '.vw-title', '.vw-nav', '.vw-header', '.vw-head',
    '#comments', '#comments-anchor', 'section#comments-anchor',
    '#episodes > section#comments-anchor', '.cs-section#comments-anchor',
    '.comment', '.comments', '.related', '.recommend',
    '.hero-v2', '.ep-list', '.episodes', '.series-list',
    'ins', '.adsbygoogle', '[data-ad]', '[data-ad-slot]',
    'div[id^="div-gpt"]', 'div[id^="google_ads"]',
    'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]'
  ].join(',');

  // 사이트 광고 슬롯(ad-guard가 검증하는 배너)입니다. 본문 이미지로 취급하지 않습니다.
  const AD_SLOT_SEL = '[data-br], [data-bs], [data-bp], [data-brs]';
  const AD_IMG_RE = /board_uploads|\\/banners?\\//i;

  function isAdSlotImg(img) {
    if (!img) return false;
    if (img.closest && img.closest(AD_SLOT_SEL)) return true;
    return AD_IMG_RE.test(img.currentSrc || img.getAttribute('src') || '');
  }

  function hasNonAdImg(el) {
    if (!el || !el.querySelectorAll) return false;
    const imgs = el.querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) {
      if (!isAdSlotImg(imgs[i])) return true;
    }
    return false;
  }

  function findComicContainer() {
    for (var i = 0; i < COMIC_CONTAINER_SELECTORS.length; i++) {
      const el = document.querySelector(COMIC_CONTAINER_SELECTORS[i]);
      if (!el) continue;
      const html = el.innerHTML || '';
      if (hasNonAdImg(el) || /webtoon_uploads|\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\//i.test(html)) {
        return el;
      }
    }
    return null;
  }

  // 본문 이미지는 광고 검증(ad-ack)이 끝난 뒤에만 내려옵니다.
  // 본문이 없으면 아직 검증 중이므로 광고 슬롯을 건드리면 안 됩니다.
  function hasComicImages() {
    const comic = findComicContainer();
    return !!comic && hasNonAdImg(comic);
  }

  function isLargePanelImg(img) {
    if (!img) return false;
    const r = img.getBoundingClientRect();
    if (r.width >= 160 && r.height >= 160) return true;
    const w = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10);
    const h = img.naturalHeight || parseInt(img.getAttribute('height') || '0', 10);
    return w >= 160 && h >= 160;
  }

  function isComicImg(img) {
    if (!img || isAdSlotImg(img)) return false;
    const attrs = ['src', 'data-src', 'data-original', 'data-lazy-src', 'data-lazy', 'data-url'];
    const comicRe = /webtoon_uploads|\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\/[^"'\\s]+\\.(?:webp|jpe?g|png|gif)/i;
    for (var i = 0; i < attrs.length; i++) {
      if (comicRe.test(img.getAttribute(attrs[i]) || '')) return true;
    }
    if (comicRe.test(img.currentSrc || img.src || '')) return true;
    if (window.__awrComicRoot && window.__awrComicRoot.contains(img) && isLargePanelImg(img)) return true;
    return false;
  }

  function hasComicContent(el) {
    if (!el || !el.querySelector) return false;
    if (el.querySelector('img')) {
      const imgs = el.querySelectorAll('img');
      for (var i = 0; i < imgs.length; i++) {
        if (isComicImg(imgs[i])) return true;
      }
    }
    return /webtoon_uploads|\\/(?:comic|webtoon|toon|episode|uploads?|data|img)\\//i.test(el.innerHTML || '');
  }

  function isHeaderBannerAd(el) {
    if (!el || !el.getAttribute) return false;
    if (el.getAttribute('data-brs') === 'header') return true;
    if (el.getAttribute('data-br-n')) return true;
    if (el.getAttribute('data-br') === '1') return true;
    return false;
  }

  function isProtected(el) {
    if (!el || !el.closest) return false;
    if (window.__awrComicRoot && window.__awrComicRoot.contains(el)) return true;
    if (el.closest(COMIC_SEL)) return true;
    if (el.closest(PAGER_SEL)) return true;
    if (hasComicContent(el)) return true;
    return false;
  }

  function forceHideElement(el) {
    if (!el || el.getAttribute('data-awr-hidden')) return;
    el.setAttribute('data-awr-hidden', '1');
    el.setAttribute('data-awr-prev-style', el.getAttribute('style') || '');
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('height', '0', 'important');
    el.style.setProperty('max-height', '0', 'important');
    el.style.setProperty('margin', '0', 'important');
    el.style.setProperty('padding', '0', 'important');
    el.style.setProperty('overflow', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  function hideElement(el) {
    if (!el || isProtected(el)) return;
    forceHideElement(el);
  }

  function hideHeaderBannerAds() {
    document.querySelectorAll(HEADER_AD_SEL).forEach(function(el) {
      if (!hasComicContent(el)) forceHideElement(el);
    });
    const main = document.querySelector('main.vw-main');
    if (!main) return;
    main.querySelectorAll(':scope > section').forEach(function(el) {
      if (hasComicContent(el)) return;
      if (isHeaderBannerAd(el) || GAMBLE_RE.test((el.textContent || '').slice(0, 600))) {
        forceHideElement(el);
      }
    });
  }

  function hideKnownChrome() {
    hideHeaderBannerAds();
    document.querySelectorAll(CHROME_SEL).forEach(function(el) {
      if (isHeaderBannerAd(el)) {
        forceHideElement(el);
        return;
      }
      if (!isProtected(el)) hideElement(el);
    });
  }

  function hideObviousAds() {
    document.querySelectorAll('div, section, aside, ins, iframe, a').forEach(function(el) {
      if (isProtected(el)) return;
      const cls = (el.className || '').toString();
      const id = (el.id || '').toString();
      const t = (el.textContent || '').slice(0, 400);
      const src = (el.getAttribute && el.getAttribute('src') || '').toLowerCase();
      const isAdFrame = el.tagName === 'IFRAME' && AD_URL_RE.test(src);
      const isAdBox = /\\b(ad|ads|advert|banner|sponsor|popup|promo|teaser|native-ad)\\b/i.test(cls + ' ' + id);
      if (GAMBLE_RE.test(t) || isAdFrame || (isAdBox && !hasComicContent(el))) {
        hideElement(el);
      }
    });
  }

  function hideInComicAdsOnly() {
    const comic = document.querySelector(COMIC_SEL);
    if (!comic) return;
    comic.querySelectorAll('div, section, aside, iframe, ins, a').forEach(function(el) {
      if (el === comic) return;
      if (hasComicContent(el)) return;
      const t = (el.textContent || '').slice(0, 200);
      const cls = (el.className || '').toString();
      if (GAMBLE_RE.test(t) || /\\b(ad|ads|advert|banner|sponsor|promo)\\b/i.test(cls)) {
        hideElement(el);
      }
    });
  }

  function hideFixedAdsOnly() {
    document.querySelectorAll('body *').forEach(function(el) {
      if (isProtected(el)) return;
      const st = window.getComputedStyle(el);
      if (st.position !== 'fixed' && st.position !== 'sticky') return;
      const z = parseInt(st.zIndex, 10);
      if (isNaN(z) || z < 80) return;
      const t = (el.textContent || '').slice(0, 200);
      const cls = (el.className || '').toString();
      if (GAMBLE_RE.test(t) || /\\b(ad|ads|banner|popup|promo)\\b/i.test(cls)) {
        hideElement(el);
      }
    });
  }

  function unlockScrollChain() {
    document.documentElement.style.setProperty('overflow-y', 'auto', 'important');
    document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
    document.documentElement.style.setProperty('touch-action', 'pan-y', 'important');
    document.body.style.setProperty('overflow-y', 'auto', 'important');
    document.body.style.setProperty('overflow-x', 'hidden', 'important');
    document.body.style.setProperty('touch-action', 'pan-y', 'important');

    const comic = document.querySelector(COMIC_SEL);
    if (!comic) return;
    var node = comic;
    while (node && node !== document.documentElement) {
      node.style.setProperty('overflow', 'visible', 'important');
      node.style.setProperty('overflow-y', 'visible', 'important');
      node.style.setProperty('height', 'auto', 'important');
      node.style.setProperty('max-height', 'none', 'important');
      node = node.parentElement;
    }
  }

  // Wrong HTML width/height (or site CSS aspect-ratio) makes width:100% + height:auto
  // stretch panels horizontally on some series. Prefer intrinsic image ratios.
  function fixComicImageAspect() {
    const comic = window.__awrComicRoot || document.querySelector(COMIC_SEL);
    if (!comic) return;
    comic.querySelectorAll('img').forEach(function(img) {
      if (!isComicImg(img) && !isLargePanelImg(img)) return;
      if (img.getAttribute('data-awr-aspect-fixed') === '1') {
        img.removeAttribute('width');
        img.removeAttribute('height');
        return;
      }
      img.setAttribute('data-awr-aspect-fixed', '1');
      img.removeAttribute('width');
      img.removeAttribute('height');
      img.style.removeProperty('aspect-ratio');
      img.style.setProperty('width', '100%', 'important');
      img.style.setProperty('max-width', '100%', 'important');
      img.style.setProperty('height', 'auto', 'important');
      img.style.setProperty('max-height', 'none', 'important');
      img.style.setProperty('aspect-ratio', 'auto', 'important');
      img.style.setProperty('object-fit', 'contain', 'important');
    });
  }

  function isAdVerificationGate() {
    const blob = ((document.documentElement && document.documentElement.innerHTML) || '')
      + ' ' + ((document.body && document.body.innerText) || '');
    return /ad_ack_required|webtoon-images:initial-ack|광고 검증이 완료되지 않았습니다|광고 검증 요청을 차단/i.test(blob);
  }

  function apply() {
    // 광고 슬롯을 가리면 initial-ack가 실패하고 본문 이미지가 403이 됩니다.
    if (isAdVerificationGate()) return false;
    // 본문 이미지가 내려오기 전(= 광고 검증 중)에는 아무것도 가리지 않습니다.
    if (!hasComicImages()) return false;

    window.__awrComicRoot = findComicContainer();
    document.documentElement.classList.add('awr-reader-mode');
    document.body.classList.add('awr-reader-mode');

    let style = document.getElementById('awr-reader-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'awr-reader-style';
      document.head.appendChild(style);
    }
    style.textContent = [
      'html.awr-reader-mode, body.awr-reader-mode {',
      '  background:#000!important;margin:0!important;padding:0!important;',
      '  overflow-y:auto!important;overflow-x:hidden!important;',
      '  touch-action:pan-y!important;-webkit-overflow-scrolling:touch!important;',
      '}',
      'body.awr-reader-mode ' + CHROME_SEL + ' {',
      '  display:none!important;height:0!important;pointer-events:none!important;',
      '}',
      'body.awr-reader-mode main.vw-main > section[data-brs="header"],',
      'body.awr-reader-mode main.vw-main > section[data-br-n],',
      'body.awr-reader-mode section[data-brs="header"],',
      'body.awr-reader-mode section[data-br="1"] {',
      '  display:none!important;height:0!important;max-height:0!important;',
      '  margin:0!important;padding:0!important;pointer-events:none!important;',
      '}',
      'body.awr-reader-mode main.vw-main,',
      'body.awr-reader-mode div.vw-imgs,',
      'body.awr-reader-mode .vw-imgs,',
      'body.awr-reader-mode #readerarea,',
      'body.awr-reader-mode .reading-content,',
      'body.awr-reader-mode .viewer,',
      'body.awr-reader-mode #viewer,',
      'body.awr-reader-mode .webtoon-viewer,',
      'body.awr-reader-mode #toon_content,',
      'body.awr-reader-mode .wt_viewer,',
      'body.awr-reader-mode .view_content,',
      'body.awr-reader-mode .comic_view,',
      'body.awr-reader-mode article.episode,',
      'body.awr-reader-mode #comic,',
      'body.awr-reader-mode .episode-content,',
      'body.awr-reader-mode .toon_viewer {',
      '  display:block!important;visibility:visible!important;',
      '  overflow:visible!important;height:auto!important;max-height:none!important;',
      '  width:100%!important;background:#000!important;pointer-events:auto!important;',
      '}',
      'body.awr-reader-mode .vw-imgs img,',
      'body.awr-reader-mode main.vw-main img,',
      'body.awr-reader-mode #readerarea img,',
      'body.awr-reader-mode .reading-content img,',
      'body.awr-reader-mode .viewer img,',
      'body.awr-reader-mode #viewer img,',
      'body.awr-reader-mode .webtoon-viewer img,',
      'body.awr-reader-mode #toon_content img,',
      'body.awr-reader-mode .wt_viewer img,',
      'body.awr-reader-mode .view_content img,',
      'body.awr-reader-mode .comic_view img,',
      'body.awr-reader-mode article.episode img,',
      'body.awr-reader-mode #comic img,',
      'body.awr-reader-mode .episode-content img,',
      'body.awr-reader-mode .toon_viewer img {',
      '  display:block!important;width:100%!important;max-width:100%!important;',
      '  height:auto!important;max-height:none!important;',
      '  aspect-ratio:auto!important;object-fit:contain!important;',
      '  visibility:visible!important;opacity:1!important;',
      '}',
      'body.awr-reader-mode .vw-bot-mini, body.awr-reader-mode .vw-bot {',
      '  display:block!important;visibility:visible!important;pointer-events:auto!important;',
      '}'
    ].join('\\n');

    hideKnownChrome();
    hideObviousAds();
    hideInComicAdsOnly();
    hideFixedAdsOnly();
    unlockScrollChain();
    fixComicImageAspect();

    if (!window.__awrReaderJumpedToComic) {
      const comic = window.__awrComicRoot || document.querySelector(COMIC_SEL);
      if (comic) {
        window.__awrReaderJumpedToComic = true;
        const top = comic.getBoundingClientRect().top + window.scrollY - 8;
        window.scrollTo(0, Math.max(0, top));
      }
    }
    return true;
  }

  function installObserver() {
    if (window.__awrReaderObserver || !document.body) return;
    let pending = false;
    window.__awrReaderObserver = new MutationObserver(function() {
      if (pending || !window.__awrReaderApply) return;
      pending = true;
      requestAnimationFrame(function() {
        pending = false;
        if (!window.__awrReaderApply) return;
        hideHeaderBannerAds();
        hideKnownChrome();
        hideObviousAds();
        hideInComicAdsOnly();
        hideFixedAdsOnly();
        fixComicImageAspect();
      });
    });
    window.__awrReaderObserver.observe(document.body, { childList: true, subtree: true });
  }

  window.__awrReaderApplyFn = apply;
  if (!window.__awrReaderApply) {
    // 검증 중이라 적용을 미뤘으면 observer도 달지 않습니다(달면 광고 슬롯을 먼저 가려 버립니다).
    if (apply()) {
      window.__awrReaderApply = true;
      installObserver();
    }
    return window.__awrReaderApply === true;
  }
  return apply();
})()
''';

  /// 댓글만 가립니다. 광고 슬롯은 검증(ad_ack)이 끝나기 전에 숨기지 않습니다.
  /// `main.vw-main`(광고 슬롯의 부모)과 그 안의 img는 건드리지 않습니다.
  /// ad-guard가 슬롯/배너의 계산 스타일 변조(css_spoofed)를 검사합니다.
  static const readerModeEarlyCss = '''
(function() {
  if (document.getElementById('awr-reader-early')) return;
  const s = document.createElement('style');
  s.id = 'awr-reader-early';
  s.textContent = [
    '#comments-anchor,section#comments-anchor,#episodes>section#comments-anchor{',
    'display:none!important;height:0!important;pointer-events:none!important;',
    '}',
    'div.vw-imgs,.vw-imgs,#readerarea,.reading-content,.viewer,#viewer,.webtoon-viewer,',
    '#toon_content,.wt_viewer,.view_content,.comic_view,article.episode,#comic,.episode-content,.toon_viewer,',
    '.vw-imgs img,#readerarea img,.reading-content img,.viewer img,#viewer img,.webtoon-viewer img,',
    '#toon_content img,.wt_viewer img,.view_content img,.comic_view img,article.episode img,#comic img{',
    'display:block!important;visibility:visible!important;height:auto!important;',
    'max-height:none!important;aspect-ratio:auto!important;object-fit:contain!important;',
    '}'
  ].join('');
  (document.head || document.documentElement).appendChild(s);
})();
''';

  static const browseModeEarlyCss = '''
(function() {
  if (document.getElementById('awr-browse-early')) return;
  const s = document.createElement('style');
  s.id = 'awr-browse-early';
  s.textContent = [
    'section[data-brs="header"],section[data-br="1"],[data-brs="header"],[data-br-n],',
    'main.vw-main>section[data-brs="header"],#comments-anchor,section#comments-anchor,',
    'ins,.adsbygoogle,div[id^="div-gpt"]{',
    'display:none!important;height:0!important;pointer-events:none!important;',
    '}'
  ].join('');
  (document.head || document.documentElement).appendChild(s);
})();
''';

  static const applyBrowseMode = '''
(function() {
  const GAMBLE_RE = /casino|betting|\\bbet\\b|slot|poker|toto|gambl|payback|카지노|베팅|토토|슬롯|첫충|페이백|가입코드/i;
  const AD_SEL = [
    'section[data-brs="header"]', 'section[data-br="1"]', '[data-brs="header"]', '[data-br-n]',
    'main.vw-main > section[data-brs="header"]', 'ins', '.adsbygoogle',
    'div[id^="div-gpt"]', 'iframe[src*="doubleclick"]',
    '#comments-anchor', 'section#comments-anchor', '#episodes > section#comments-anchor'
  ].join(',');

  function hideComments() {
    document.querySelectorAll(
      '#comments-anchor, section#comments-anchor, #episodes > section#comments-anchor, .cs-section#comments-anchor'
    ).forEach(function(el) {
      el.style.setProperty('display', 'none', 'important');
      el.style.setProperty('height', '0', 'important');
      el.style.setProperty('overflow', 'hidden', 'important');
      el.style.setProperty('pointer-events', 'none', 'important');
    });
  }

  function hideAds() {
    hideComments();
    document.querySelectorAll(AD_SEL).forEach(function(el) {
      el.style.setProperty('display', 'none', 'important');
      el.style.setProperty('height', '0', 'important');
      el.style.setProperty('pointer-events', 'none', 'important');
    });
    const CATALOG = 'a[href*="/webtoon/"], a[href*="/manhwa/"], a[href*="/novel/"], .card-grid, .work-card-grid, ul.ep-list, ul.ep-list-v2, #episodes';
    function keepsCatalog(el) {
      if (el.matches && el.matches(CATALOG)) return true;
      return !!el.querySelector(CATALOG);
    }
    document.querySelectorAll('div, section, aside').forEach(function(el) {
      // 목록이 나중에 붙으면, 예전에 숨긴 칸을 다시 보여 줍니다.
      if (keepsCatalog(el)) {
        if (el.getAttribute('data-awr-browse-hide') === '1') {
          el.style.removeProperty('display');
          el.style.removeProperty('height');
          el.style.removeProperty('pointer-events');
          el.removeAttribute('data-awr-browse-hide');
        }
        return;
      }
      const t = (el.textContent || '').slice(0, 300);
      if (!GAMBLE_RE.test(t)) return;
      el.setAttribute('data-awr-browse-hide', '1');
      el.style.setProperty('display', 'none', 'important');
    });
  }

  hideAds();
  if (!window.__awrBrowseObserver && document.body) {
    window.__awrBrowseObserver = new MutationObserver(hideAds);
    window.__awrBrowseObserver.observe(document.body, { childList: true, subtree: true });
  }
})();
''';

  static const extractBrowseSeries = '''
(function() {
  /*AWR_EXTRACT_BROWSE_SERIES*/
  function findSeriesCard(a) {
    return a.closest('article, li, .card, .item, [class*="thumb"], [class*="item"], [class*="card"], [class*="poster"], [class*="webtoon"]') || a;
  }

  function seriesIdFromCard(a, fallbackId) {
    const card = findSeriesCard(a);
    if (!card) return fallbackId;
    var best = fallbackId || '';
    card.querySelectorAll('a[href*="/webtoon/"]').forEach(function(link) {
      const href = link.getAttribute('href') || link.href || '';
      const m = href.match(/\\/webtoon\\/([^/?#]+)/);
      if (!m || !m[1]) return;
      const candidate = m[1];
      if (!best || (candidate.startsWith(best) && candidate.length > best.length)) {
        best = candidate;
      } else if (candidate.length > best.length && !best.startsWith(candidate)) {
        best = candidate;
      }
    });
    const rawId = card.getAttribute('data-source-work-id')
      || card.getAttribute('data-work-id');
    if (rawId) {
      const trimmed = String(rawId).trim();
      const fromData = trimmed.includes('/webtoon/')
        ? trimmed.split('/webtoon/').pop().split('/')[0].split('?')[0]
        : trimmed;
      if (fromData.length > best.length) best = fromData;
    }
    return seriesIdFromPageJson(best);
  }

  function seriesIdFromPageJson(prefix) {
    if (!prefix) return prefix;
    var best = prefix;
    try {
      const marker = '"sourceWorkId":"' + prefix;
      const html = document.documentElement.innerHTML || '';
      var start = 0;
      while (true) {
        const idx = html.indexOf(marker, start);
        if (idx < 0) break;
        const valueStart = idx + '"sourceWorkId":"'.length;
        const end = html.indexOf('"', valueStart);
        if (end < 0) break;
        const candidate = html.slice(valueStart, end);
        if (candidate.length > best.length) best = candidate;
        start = idx + 1;
      }
    } catch (e) {}
    return best;
  }

  function normalizeUrl(href, anchor) {
    try {
      const u = new URL(href, location.origin);
      var path = u.pathname;
      if (path.endsWith('/')) path = path.slice(0, -1);
      const parts = path.split('/').filter(function(p) { return !!p; });
      if (parts.length < 2 || (parts[0] !== 'webtoon' && parts[0] !== 'manhwa')) return '';
      if (parts[1] === 'updates' || parts[1] === 'new') return '';
      var id = parts[1];
      if (anchor && parts[0] === 'webtoon') id = seriesIdFromCard(anchor, id);
      return u.origin + '/' + parts[0] + '/' + id;
    } catch (e) { return ''; }
  }

  function titleFromAnchor(a) {
    const card = a.closest('article, li, .card, .item, [class*="thumb"], [class*="item"], [class*="card"]') || a;
    const img = card.querySelector('img');
    if (img) {
      const alt = (img.getAttribute('alt') || '').trim();
      if (alt && alt.length > 1) return alt;
    }
    const titleEl = card.querySelector('[class*="title"], h2, h3, h4, strong, .name');
    if (titleEl) {
      const t = (titleEl.textContent || '').replace(/\\s+/g, ' ').trim();
      if (t) return t;
    }
    const t = (a.textContent || '').replace(/\\s+/g, ' ').trim();
    return t;
  }

  function coverFromAnchor(a) {
    const card = a.closest('article, li, .card, .item, [class*="thumb"], [class*="item"]') || a;
    const img = card.querySelector('img');
    if (!img) return '';
    const attrs = ['src', 'data-src', 'data-original', 'data-lazy-src', 'data-lazy'];
    for (var i = 0; i < attrs.length; i++) {
      const v = img.getAttribute(attrs[i]) || '';
      if (!v) continue;
      const normalized = v.startsWith('http') ? v : (location.origin + (v.startsWith('/') ? v : '/' + v));
      if (/webtoon_uploads|\\/thumbs?\\/|\\/black\\/thumbs\\/|\\/board_uploads\\/|\\/comics\\/|lezhin\\.com\\/|\\.(png|jpe?g|webp|gif|avif)/i.test(normalized)) {
        return normalized;
      }
    }
    const direct = img.currentSrc || img.src || '';
    return direct.startsWith('http') ? direct : '';
  }

  const seen = new Set();
  const series = [];
  document.querySelectorAll('a[href*="/webtoon/"], a[href*="/manhwa/"]').forEach(function(a) {
    const url = normalizeUrl(a.getAttribute('href') || a.href, a);
    if (!url || seen.has(url)) return;
    const title = titleFromAnchor(a);
    if (!title || title.length < 2) return;
    seen.add(url);
    series.push({ url: url, title: title, coverUrl: coverFromAnchor(a) });
  });

  var page = 1;
  var maxPage = 1;
  const active = document.querySelector('.pagination .active, .paging .on, [class*="pagination"] .current, .page-item.active');
  if (active) {
    const n = parseInt((active.textContent || '').trim(), 10);
    if (!isNaN(n)) page = n;
  }
  document.querySelectorAll('a[href*="page="], a[href*="&p="], .pagination a, .paging a').forEach(function(a) {
    const href = a.getAttribute('href') || '';
    const m = href.match(/[?&](?:page|p)=(\\d+)/i);
    if (m) {
      const n = parseInt(m[1], 10);
      if (!isNaN(n) && n > maxPage) maxPage = n;
    }
    const t = parseInt((a.textContent || '').trim(), 10);
    if (!isNaN(t) && t > maxPage) maxPage = t;
  });

  return JSON.stringify({ series: series, page: page, maxPage: maxPage });
})()
''';

  static const injectBrowseAddButtons = '''
(function() {
  function findSeriesCard(a) {
    return a.closest(
      'article, li, .card, .item, [class*="thumb"], [class*="item"], [class*="card"], [class*="poster"], [class*="webtoon"]'
    ) || a;
  }

  function seriesIdFromCard(a, fallbackId) {
    const card = findSeriesCard(a);
    if (!card) return fallbackId;
    var best = fallbackId || '';
    card.querySelectorAll('a[href*="/webtoon/"]').forEach(function(link) {
      const href = link.getAttribute('href') || link.href || '';
      const m = href.match(/\\/webtoon\\/([^/?#]+)/);
      if (!m || !m[1]) return;
      const candidate = m[1];
      if (!best || (candidate.startsWith(best) && candidate.length > best.length)) {
        best = candidate;
      } else if (candidate.length > best.length && !best.startsWith(candidate)) {
        best = candidate;
      }
    });
    const rawId = card.getAttribute('data-source-work-id')
      || card.getAttribute('data-work-id');
    if (rawId) {
      const trimmed = String(rawId).trim();
      const fromData = trimmed.includes('/webtoon/')
        ? trimmed.split('/webtoon/').pop().split('/')[0].split('?')[0]
        : trimmed;
      if (fromData.length > best.length) best = fromData;
    }
    return seriesIdFromPageJson(best);
  }

  function seriesIdFromPageJson(prefix) {
    if (!prefix) return prefix;
    var best = prefix;
    try {
      const marker = '"sourceWorkId":"' + prefix;
      const html = document.documentElement.innerHTML || '';
      var start = 0;
      while (true) {
        const idx = html.indexOf(marker, start);
        if (idx < 0) break;
        const valueStart = idx + '"sourceWorkId":"'.length;
        const end = html.indexOf('"', valueStart);
        if (end < 0) break;
        const candidate = html.slice(valueStart, end);
        if (candidate.length > best.length) best = candidate;
        start = idx + 1;
      }
    } catch (e) {}
    return best;
  }

  function normalizeUrl(href, anchor) {
    try {
      const u = new URL(href, location.origin);
      var path = u.pathname;
      if (path.endsWith('/')) path = path.slice(0, -1);
      const parts = path.split('/').filter(function(p) { return !!p; });
      if (parts.length < 2 || (parts[0] !== 'webtoon' && parts[0] !== 'manhwa')) return '';
      if (parts[1] === 'updates' || parts[1] === 'new') return '';
      var id = parts[1];
      if (anchor && parts[0] === 'webtoon') id = seriesIdFromCard(anchor, id);
      return u.origin + '/' + parts[0] + '/' + id;
    } catch (e) { return ''; }
  }

  function titleFromAnchor(a) {
    const card = findSeriesCard(a);
    const img = card.querySelector('img');
    if (img && img.alt) return img.alt.trim();
    const titleEl = card.querySelector('[class*="title"], h2, h3, h4, strong');
    if (titleEl) return (titleEl.textContent || '').replace(/\\s+/g, ' ').trim();
    return (a.textContent || '').replace(/\\s+/g, ' ').trim();
  }

  function seriesIdFromUrl(url) {
    try {
      var path = new URL(url).pathname;
      if (path.endsWith('/')) path = path.slice(0, -1);
      const parts = path.split('/').filter(function(p) { return !!p; });
      if (parts.length >= 2 && (parts[0] === 'webtoon' || parts[0] === 'manhwa')) {
        return parts[0] === 'manhwa' ? ('mh-' + parts[1]) : parts[1];
      }
    } catch (e) {}
    return '';
  }

  function isAlreadyInLibrary(url) {
    const ids = window.__awrExistingSeriesIds;
    if (!ids) return false;
    const id = seriesIdFromUrl(url);
    return !!(id && ids.has(id));
  }

  function styleAddButton(btn, exists) {
    if (exists) {
      btn.textContent = '\\u2713';
      btn.setAttribute('data-awr-exists', '1');
      btn.style.background = '#4caf50';
      btn.style.fontSize = '16px';
    } else {
      btn.textContent = '+';
      btn.removeAttribute('data-awr-exists');
      btn.style.background = '#7c4dff';
      btn.style.fontSize = '20px';
    }
  }

  function injectBrowseAddButtons() {
    const seen = new Set();
    document.querySelectorAll('a[href*="/webtoon/"], a[href*="/manhwa/"]').forEach(function(a) {
      const url = normalizeUrl(a.getAttribute('href') || a.href);
      if (!url || seen.has(url)) return;
      const title = titleFromAnchor(a);
      if (!title) return;
      seen.add(url);
      const card = findSeriesCard(a);
      if (!card) return;
      const exists = isAlreadyInLibrary(url);
      const pos = window.getComputedStyle(card).position;
      if (pos === 'static') card.style.position = 'relative';
      var btn = card.querySelector('[data-awr-add]');
      if (!btn) {
        btn = document.createElement('button');
        btn.setAttribute('data-awr-add', '1');
        btn.type = 'button';
        btn.style.cssText = [
          'position:absolute', 'top:6px', 'right:6px', 'z-index:9999',
          'width:32px', 'height:32px', 'border:none', 'border-radius:16px',
          'color:#fff', 'font-weight:700',
          'line-height:1', 'cursor:pointer', 'box-shadow:0 2px 8px rgba(0,0,0,.35)',
          'pointer-events:auto'
        ].join(';');
        card.appendChild(btn);
      }
      styleAddButton(btn, exists);
      btn.onclick = function(e) {
        e.preventDefault();
        e.stopPropagation();
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler(
            'awrBrowseAdd',
            JSON.stringify({ url: url, title: title, alreadyExists: exists })
          );
        }
      };
    });
    hookSortTabs();
  }

  function hookSortTabs() {
    document.querySelectorAll('.sort-tabs, .manhwa-toolbar .sort-tabs').forEach(function(tabs) {
      tabs.querySelectorAll('button, a, [role="tab"], span, div').forEach(function(el) {
        if (el.getAttribute('data-awr-sort-hook')) return;
        const label = (el.textContent || '').replace(/\\s+/g, '').trim();
        if (!label || label.length > 8) return;
        if (!/(최신순|신작순|북마크순|조회순|평점순|화수순)/.test(label)) return;
        el.setAttribute('data-awr-sort-hook', '1');
        el.addEventListener('click', function() {
          setTimeout(injectBrowseAddButtons, 350);
          setTimeout(injectBrowseAddButtons, 900);
          setTimeout(injectBrowseAddButtons, 1800);
        }, true);
      });
    });
  }

  window.__awrInjectBrowseButtons = injectBrowseAddButtons;
  injectBrowseAddButtons();

  if (!window.__awrBrowseInjectObserver && document.body) {
    let pending = false;
    window.__awrBrowseInjectObserver = new MutationObserver(function() {
      if (pending) return;
      pending = true;
      requestAnimationFrame(function() {
        pending = false;
        injectBrowseAddButtons();
      });
    });
    window.__awrBrowseInjectObserver.observe(document.body, {
      childList: true,
      subtree: true
    });
  }
})();
''';

  static bool isCloudflareHtml(String? html) {
    if (html == null || html.isEmpty) return false;
    return html.contains('Just a moment') ||
        html.contains('challenge-platform') ||
        html.contains('cf-browser-verification');
  }

  static bool isAdVerificationHtml(String? html) {
    if (html == null || html.isEmpty) return false;
    return html.contains('ad_ack_required') ||
        html.contains('webtoon-images:initial-ack') ||
        html.contains('광고 검증이 완료되지 않았습니다') ||
        html.contains('광고 검증 요청을 차단');
  }

  /// Next.js 클라이언트가 실제로 404 UI를 그린 경우입니다.
  /// 회차 SSR HTML에는 flight payload에 404 문자열이 섞여 있어
  /// raw HTML만으로는 판단하지 않습니다.
  static bool isNextNotFoundHtml(String? html) {
    if (html == null || html.isEmpty) return false;
    if (html.contains('ep-row-v2-link')) return false;
    if (html.contains('vw-main') || html.contains('class="vw-')) return false;
    return html.contains('This page could not be found') ||
        html.contains('404: This page could not be found') ||
        html.contains('next-error-h1');
  }

  /// 화면에 보이는 Next.js/CDN 404인지 (회차 뷰어용).
  static const isVisibleNotFoundPage = '''
(function() {
  try {
    var h1 = document.querySelector('h1.next-error-h1');
    if (h1) return true;
    if (document.querySelector('main.vw-main, .vw-imgs')) return false;
    var title = (document.title || '').trim();
    if (/^404\\b/i.test(title) || /could not be found/i.test(title)) return true;
    if (/^Not Found\$/i.test(title)) return true;
    var body = ((document.body && document.body.innerText) || '').trim();
    if (/^Not Found\$/i.test(body)) return true;
    if (/^404\\s*This page could not be found/i.test(body)) return true;
    if (/This page could not be found/i.test(body) && body.length < 400) return true;
    if (/(페이지를 찾을 수 없|존재하지 않는 페이지|존재하지 않는 회차)/.test(body) && body.length < 500) return true;
    if (/^Not Found\\b/i.test(body) && body.length < 120) return true;
  } catch (e) {}
  return false;
})();
''';

  /// SSR로 뷰어가 그려진 뒤 Next.js가 404로 바꾸면 한 번 하드 리로드합니다.
  static const recoverClientNotFound = '''
(function() {
  if (window.__awrNfGuard) return;
  window.__awrNfGuard = true;
  var key = 'awr-nf-reload:' + location.pathname;
  var tried = false;
  try { tried = sessionStorage.getItem(key) === '1'; } catch (e) {}
  function isNf() {
    try {
      if (document.querySelector('main.vw-main, .vw-imgs')) return false;
      if (document.querySelector('h1.next-error-h1')) return true;
      var body = ((document.body && document.body.innerText) || '').trim();
      if (/^Not Found\$/i.test(body)) return true;
      if (/^404\\s*This page could not be found/i.test(body)) return true;
      if (/This page could not be found/i.test(body) && body.length < 400) return true;
    } catch (e) {}
    return false;
  }
  function recover() {
    if (tried || !isNf()) return;
    tried = true;
    try { sessionStorage.setItem(key, '1'); } catch (e) {}
    location.replace(location.pathname + location.search);
  }
  try {
    new MutationObserver(recover).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } catch (e) {}
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', recover);
  } else {
    recover();
  }
  window.addEventListener('load', recover);
})();
''';

  /// SSR 회차 HTML이 Next.js 404로 치환되기 전에 보관합니다.
  static const captureSsrHtml = '''
(function() {
  if (window.__awrSsrCaptureInstalled) return;
  window.__awrSsrCaptureInstalled = true;
  function snap() {
    try {
      var html = document.documentElement && document.documentElement.innerHTML;
      if (html && html.indexOf('ep-row-v2-link') >= 0) {
        window.__awrCapturedHtml = html;
      }
    } catch (e) {}
  }
  snap();
  try {
    new MutationObserver(snap).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } catch (e) {}
})();
''';
}
