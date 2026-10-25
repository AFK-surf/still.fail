// What the stories are measured by (docs/ui-panels.md; test/browser/stories.mjs runs them in each story's page): each
// a function run in the page, returning what it measured and what is off. Told to `mark`, each also marks what is off
// (data-off, saying why), as the web app's development build does as it runs (web/src/dev/offs.ts).

/**
 * Every corner: each rounded thing with a ground of its own or to press, standing in a corner of the rounded box drawn
 * round it, is as far from both edges of that corner and rounded as the box less that distance (concentric), and no
 * shorter than that rounding asks.
 */
export function corners(mark = false) {
  const say = (el, why) => { wrong.push(why); if (mark) el.setAttribute('data-off', why); };
  const px = (v) => parseFloat(v) || 0;
  const drawn = (cs) => {
    const bg = cs.backgroundColor;
    const hasBg = bg && bg !== 'transparent' && !/rgba\([^)]*,\s*0\)$/.test(bg);
    return hasBg || px(cs.borderTopWidth) > 0 || (cs.boxShadow && cs.boxShadow !== 'none') || cs.backdropFilter !== 'none';
  };
  const radius = (cs) => Math.max(px(cs.borderTopLeftRadius), px(cs.borderTopRightRadius), px(cs.borderBottomLeftRadius), px(cs.borderBottomRightRadius));
  const name = (el) => (el.className && el.className.toString().split(' ').find((c) => /__/.test(c))?.replace(/__.*/, '')) || el.tagName.toLowerCase();
  /** What shows of it: cut by what clips between it and `upTo`. */
  const shown = (el, upTo) => {
    const b = el.getBoundingClientRect();
    const r = { left: b.left, right: b.right, top: b.top, bottom: b.bottom };
    for (let a = el.parentElement; a && a !== upTo; a = a.parentElement) {
      const o = getComputedStyle(a);
      if (o.overflowX === 'visible' && o.overflowY === 'visible') continue;
      const c = a.getBoundingClientRect();
      r.left = Math.max(r.left, c.left); r.right = Math.min(r.right, c.right); r.top = Math.max(r.top, c.top); r.bottom = Math.min(r.bottom, c.bottom);
    }
    return r.right - r.left >= b.width - 0.5 && r.bottom - r.top >= b.height - 0.5 ? b : null;
  };
  const wrong = [];
  let measured = 0;
  for (const el of document.querySelectorAll('body *')) {
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || px(cs.opacity) === 0 && cs.opacity !== '') continue;
    const re = radius(cs);
    if (re < 0.5) continue;
    // What shows a ground of its own (now, or while pointed at: what is pressed); not a picture or a mark.
    if (/^(IMG|SVG|VIDEO|CANVAS)$/i.test(el.tagName)) continue;
    // A placeholder's bars stand for words to come (web/ui waiting.tsx WaitShapes), which have no ground of their own.
    if (el.closest('[data-placeholder]')) continue;
    // A slider's knob goes where the value is: not set in a corner.
    if (el.closest('[role=slider]')) continue;
    // What turns for ever (a spinner) is measured at whatever angle it is caught, its box as large as that turn makes it.
    if (el.getAnimations().some((a) => a.effect?.getTiming().iterations === Infinity)) continue;
    const pressed = el.matches('button, a[href], [role=button], [role=menuitem], [role=menuitemradio], [role=menuitemcheckbox], [role=option], [role=tab], input, textarea, select, summary');
    if (!drawn(cs) && !pressed) continue;
    const b = el.getBoundingClientRect();
    if (b.width < 8 || b.height < 8) continue;
    // The rounded box drawn round it: one drawn, or one pressed (a row whose ground shows under the pointer: what is
    // in it stands in that ground's corner then).
    // A row (wider than tall), not an icon's round button: a mark in the middle of that is its own.
    const pressedBox = (b) => b.matches('button, a[href], [role=button], [role=menuitem], [role=menuitemradio], [role=menuitemcheckbox], [role=option]')
      && b.getBoundingClientRect().width > b.getBoundingClientRect().height * 1.5;
    let box = el.parentElement, bs = null;
    while (box && box !== document.body) {
      bs = getComputedStyle(box);
      if (radius(bs) >= 0.5 && (drawn(bs) || pressedBox(box))) break;
      box = box.parentElement;
    }
    if (!box || box === document.body) continue;
    const r = shown(el, box);
    if (!r) continue;
    const c = box.getBoundingClientRect();
    const rb = radius(bs);
    const inL = c.left + px(bs.borderLeftWidth), inR = c.right - px(bs.borderRightWidth), inT = c.top + px(bs.borderTopWidth), inB = c.bottom - px(bs.borderBottomWidth);
    const gl = r.left - inL, gr = inR - r.right, gt = r.top - inT, gb = inB - r.bottom;
    if (Math.min(gl, gr, gt, gb) < -0.5) continue; // reaching out of it (a badge on its edge): not in its corner
    // In a corner: within the box's curve of both edges that meet there.
    const corners = [['top left', gl, gt, 'borderTopLeftRadius'], ['top right', gr, gt, 'borderTopRightRadius'], ['bottom left', gl, gb, 'borderBottomLeftRadius'], ['bottom right', gr, gb, 'borderBottomRightRadius']];
    // A button (its ground shows under the pointer; not a switch, a row's) set as far from both edges of a corner, further
    // in than that, is still set in it (in where words stand, docs/ui-panels.md): its ground must follow the corner too.
    const button = el.matches('button, [role=button], a[href]') && !el.matches('[role=switch]');
    for (const [where, g1, g2, prop] of corners) {
      // Its corner as drawn (no more than half its side), and what stands in it: within a little over half of that from
      // both edges (further in, it is beside the corner, not in it); a button set evenly in it, within all of it.
      const rbc = Math.min(px(bs[prop]), c.width / 2, c.height / 2);
      const reach = button && Math.abs(g1 - g2) <= 1 ? rbc : rbc * 0.6;
      if (rbc < 0.5 || g1 > reach || g2 > reach) continue;
      measured++;
      const who = `${name(box)} › ${name(el)} (${where})`;
      if (Math.abs(g1 - g2) > 1) { say(el, `${who}: ${g1.toFixed(1)} from the side, ${g2.toFixed(1)} from the ${where.split(' ')[0]}`); continue; }
      // Short enough to round as far as the corner asks (a pill: its half height): else a crescent stands beside it. In
      // round terms: a squarer corner (superellipse) is drawn larger by --corner-scale than the round one it matches.
      const scale = /superellipse/.test(bs.cornerShape || '') ? px(bs.getPropertyValue('--corner-scale')) || 1 : 1;
      const asks = rbc / scale - g1, half = Math.min(r.height, r.width) / 2;
      if (asks > half + 1) { say(el, `${who}: too short to follow the corner (it asks ${asks.toFixed(1)}, half its side is ${half.toFixed(1)})`); continue; }
      // Rounded as the corner is (both squarer, or both round): the corner less the distance, as set; a round thing (a
      // pill) in a squarer corner: in round terms, the corner as the round one it matches.
      const squarer = (st) => /superellipse/.test(st.cornerShape || '');
      const roundIn = squarer(bs) && !squarer(cs);
      const own = Math.min(px(cs[prop]), r.height / 2, r.width / 2);
      const want = Math.min(Math.max((roundIn ? rbc / scale : rbc) - g1, 0), r.height / 2, r.width / 2);
      if (Math.abs(own - want) > 1) say(el, `${who}: rounded ${own.toFixed(1)}, ${g1.toFixed(1)} in from a corner of ${rbc.toFixed(1)} (wants ${want.toFixed(1)})`);
    }
  }
  return { measured, wrong };
}

/**
 * Every small panel (a surface saying its --panel-pad): its corner its inner one and its padding together; padded 6
 * (all but ⌘K, a dialog); a panel of words' blocks in by 10 and as far from its top and foot; its rows' words in by 10;
 * what sits in its corners (a button: as far in as the words stand) as far from both edges and concentric.
 */
export function panels(mark = false) {
    // A row's padding: the words in a small panel stand in by it more than what has a ground (align.ts TEXT_IN).
    const TEXT = 10;
    const say = (el, why) => { wrong.push(why); if (mark) el.setAttribute('data-off', why); };
    const px = (v) => parseFloat(v) || 0;
    const resolve = (el, value) => {
      const probe = document.createElement('div');
      probe.style.cssText = `position:absolute;visibility:hidden;padding:0;border:0;margin:0;width:${value}`;
      el.appendChild(probe);
      const w = probe.getBoundingClientRect().width;
      probe.remove();
      return w;
    };
    const wrong = [];
    let surfaces = 0, corners = 0;
    for (const s of document.querySelectorAll('body *')) {
      const cs = getComputedStyle(s);
      // A surface says its own --panel-pad (what sits in it only inherits it) and is padded by it.
      const padVar = cs.getPropertyValue('--panel-pad').trim();
      const parentVar = s.parentElement ? getComputedStyle(s.parentElement).getPropertyValue('--panel-pad').trim() : '';
      if (!padVar || padVar === parentVar || !s.getClientRects().length) continue;
      if (Math.abs(px(cs.paddingRight) - resolve(s, 'var(--panel-pad)')) > 0.5) continue;
      surfaces++;
      const pad = resolve(s, 'var(--panel-pad)'), inner = resolve(s, 'var(--panel-in)');
      const name = s.className.toString().split(' ')[0];
      const outer = px(cs.borderTopLeftRadius);
      if (Math.abs(outer - (inner + pad)) > 0.5) say(s, `${name}: corner ${outer}, not ${inner} + ${pad}`);
      // A small panel (all but ⌘K, a dialog) is padded 6 (docs/ui-panels.md).
      const small = !/Switcher/.test(s.className.toString());
      if (small && Math.abs(pad - 6) > 0.5) say(s, `${name}: padded ${pad}, not 6`);
      const edgeLeft = s.getBoundingClientRect().left + px(cs.borderLeftWidth);
      // A panel of words: each block not at its padding stands in by a row's padding (10).
      if (small && cs.getPropertyValue('--panel-kind').trim() === 'card') {
        for (const c of s.children) {
          if (/panelEdge/.test(c.className.toString())) continue;
          const cc = getComputedStyle(c), who = `${name} › ${c.className.toString().split(' ')[0] || c.tagName}`;
          const pl = px(cc.paddingLeft);
          if (Math.abs(pl - 10) > 0.5) say(c, `${who}: words in by ${pl}, not 10`);
          // As far from the top and the foot as from the sides.
          if (c === s.firstElementChild && Math.abs(px(cc.paddingTop) - 10) > 0.5) say(c, `${who}: ${px(cc.paddingTop)} above the words, not 10`);
          if (c === s.lastElementChild && Math.abs(px(cc.paddingBottom) - 10) > 0.5) say(c, `${who}: ${px(cc.paddingBottom)} under the words, not 10`);
        }
      }
      // A row (as wide as the panel's room, at its padding, with words): its words in by a row's padding (10).
      if (small) {
        const room = s.getBoundingClientRect().width - 2 * px(cs.borderLeftWidth) - 2 * pad;
        for (const d of s.querySelectorAll('button, a, [role=menuitem], [role=option], [role=menuitemradio], [role=menuitemcheckbox]')) {
          const r = d.getBoundingClientRect();
          if (!r.width || Math.abs(r.left - edgeLeft - pad) > 0.6 || r.width < room * 0.8 || !d.textContent.trim()) continue;
          const pl = px(getComputedStyle(d).paddingLeft);
          if (pl < 9.5) say(d, `${name} › ${d.className.toString().split(' ')[0] || d.tagName}: a row's words in by ${pl}, not 10`);
        }
      }
      // What sits at one of its corners (within its padding of two edges that meet): as far from both, and rounded as
      // the surface's corner less that distance.
      const box = s.getBoundingClientRect(), border = px(cs.borderRightWidth);
      const near = pad + 1;
      for (const d of s.querySelectorAll('*')) {
        // As much of it as shows: cut by what scrolls or clips between it and the surface.
        const b = d.getBoundingClientRect();
        const r = { left: b.left, right: b.right, top: b.top, bottom: b.bottom };
        for (let a = d.parentElement; a && a !== s; a = a.parentElement) {
          const o = getComputedStyle(a);
          if (o.overflowX === 'visible' && o.overflowY === 'visible') continue;
          const c = a.getBoundingClientRect();
          r.left = Math.max(r.left, c.left); r.right = Math.min(r.right, c.right); r.top = Math.max(r.top, c.top); r.bottom = Math.min(r.bottom, c.bottom);
        }
        r.width = r.right - r.left; r.height = r.bottom - r.top;
        if (r.width <= 0 || r.height <= 0 || r.height < b.height - 0.5 || r.width < b.width - 0.5) continue;
        const dr = px(getComputedStyle(d).borderBottomRightRadius);
        if (!r.width || !r.height || !dr) continue;
        const gl = r.left - box.left - border, gr = box.right - border - r.right, gt = r.top - box.top - border, gb = box.bottom - border - r.bottom;
        // A button by a corner (its ground shows under the pointer) counts as in it as far in as the words stand (the
        // padding and a row's): there too it is as far from both edges and concentric, or it stands where words do
        // with a ground the corner does not follow. What sits in a control of its own (a segmented control's options)
        // is that control's, and a switch is a row's.
        let reach = near;
        if (small && d.matches('button, [role=button], a[href]') && !d.matches('[role=switch]')) {
          let own = false;
          for (let a = d.parentElement; a && a !== s; a = a.parentElement) {
            const o = getComputedStyle(a), bg = o.backgroundColor;
            if ((bg && bg !== 'transparent' && !/rgba\([^)]*,\s*0\)$/.test(bg)) || px(o.borderTopWidth) > 0) { own = true; break; }
          }
          if (!own) reach = pad + TEXT + 1;
        }
        const side = gl <= reach ? gl : gr <= reach ? gr : null, end = gt <= reach ? gt : gb <= reach ? gb : null;
        if (side === null || end === null || side < -0.5 || end < -0.5) continue;
        corners++;
        const who = `${name} › ${d.className.toString().split(' ')[0] || d.tagName}`;
        if (Math.abs(side - end) > 0.75) say(d, `${who}: ${side.toFixed(1)} from the side, ${end.toFixed(1)} from the top or foot`);
        else if (Math.abs(Math.min(dr, r.height / 2, r.width / 2) - Math.min(outer - side, r.height / 2, r.width / 2)) > 0.75) say(d, `${who}: corner ${dr} ${side.toFixed(1)} in from a corner of ${outer}`);
      }
    }
    return { surfaces, corners, wrong };
}

/**
 * Contrast (docs/ui-panels.md「对比度」): what the page draws stands off what it is drawn on far enough to be seen, as
 * mbui's Tester::contrast_faults asks of the app (its contrast.mbt). What is drawn with nothing in it, its ground or,
 * where that does not show, its edge alone saying what it is (a gauge's cell, a track, a line, a placeholder's block, a
 * grip), at least 1.25:1 (WCAG 2's ratio). A ground under words, a picture or an icon is not asked: what is in it
 * carries it. Each where it is drawn, against what the browser stacks under it there (each ground as faint as what it
 * is in has made it); what lies on a picture or a video, or under something drawn over it (a dialog's scrim, a bar's
 * glass), is not asked, nor what is disabled, nor what dims the whole page, nor a ground cut out of one under it (a ring
 * round a dot, in the colour of a ground further down), nor a field (its words say it is one), nor a drawing of something
 * else ([data-depicts]: another system's screen). What loops (a placeholder's breath) is measured at its start, where it
 * is seen at its strongest. What is on its way, or lies on what is (a scrollbar's thumb fading in, a mark over another
 * fading out, a transition, an animation that ends), is not asked until all of it there is where it goes: half way it
 * is neither what it was nor what it comes to, and what it comes to may be gone (the page removes what faded out).
 */
export function contrast(mark = false) {
  const MARK = 1.25;
  const say = (el, why) => { wrong.push(why); if (mark) el.setAttribute('data-off', why); };
  const wrong = [];
  const px = (v) => parseFloat(v) || 0;
  const name = (el) => (el.className && el.className.toString().split(' ').find((c) => /__/.test(c))?.replace(/__.*/, '')) || el.tagName.toLowerCase();
  // A colour as the browser computed it, as red, green, blue and opacity (0-1): rgb() and color(srgb) read, the rest
  // (oklch(), oklab()) drawn on a pixel and read back.
  const pixel = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
  pixel.canvas.width = pixel.canvas.height = 1;
  const colours = new Map();
  const rgba = (css) => {
    let v = colours.get(css);
    if (v) return v;
    const n = css.match(/^rgba?\(([^)]*)\)$/) ?? css.match(/^color\(srgb ([^)]*)\)$/);
    if (n) {
      const parts = n[1].split(/[\s,/]+/).filter(Boolean).map(Number);
      const scale = css.startsWith('color(') ? 1 : 255;
      v = [parts[0] / scale, parts[1] / scale, parts[2] / scale, parts.length > 3 ? parts[3] : 1];
    } else {
      pixel.clearRect(0, 0, 1, 1);
      pixel.fillStyle = 'transparent';
      pixel.fillStyle = css;
      pixel.fillRect(0, 0, 1, 1);
      const d = pixel.getImageData(0, 0, 1, 1).data;
      v = [d[0] / 255, d[1] / 255, d[2] / 255, d[3] / 255];
    }
    colours.set(css, v);
    return v;
  };
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const lum = ([r, g, b]) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const laid = (under, top, a) => under.map((u, i) => u + (top[i] - u) * a);
  const same = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 0.5 / 255);
  const hex = (c) => '#' + c.map((v) => Math.round(Math.min(Math.max(v, 0), 1) * 255).toString(16).padStart(2, '0')).join('');
  const faintness = new Map();
  const faint = (el) => {
    if (!el || el === document.documentElement) return 1;
    let f = faintness.get(el);
    if (f === undefined) { f = Number(getComputedStyle(el).opacity) * faint(el.parentElement); faintness.set(el, f); }
    return f;
  };
  const pictured = (el) => /^(IMG|VIDEO|CANVAS|IFRAME|OBJECT|EMBED|PICTURE)$/i.test(el.tagName)
    || (getComputedStyle(el).backgroundImage.includes('url('));
  // What the browser draws at (x, y) under the `at`-th of `stack` (what is there, topmost first): its colour and each it
  // was on the way up (the last whole one first), null on a picture's.
  // (under all of it, the canvas: the root's ground, else the body's, which CSS paints there; white with neither)
  const root = [document.documentElement, document.body].map((u) => rgba(getComputedStyle(u).backgroundColor)).find((v) => v[3] > 0.002);
  const canvas = root ? laid([1, 1, 1], root.slice(0, 3), root[3]) : [1, 1, 1];
  const ground = (stack, at) => {
    let c = canvas;
    let beneath = [c];
    for (let i = stack.length - 1; i > at; i--) {
      const u = stack[i];
      if (pictured(u)) { c = null; beneath = []; continue; }
      const [r, g, b, a] = rgba(getComputedStyle(u).backgroundColor);
      const o = a * faint(u);
      if (o <= 0.002) continue;
      if (o >= 0.999) { c = [r, g, b]; beneath = [c]; } else if (c) { c = laid(c, [r, g, b], o); beneath.push(c); }
    }
    return c && { c, beneath };
  };
  const grounded = (u) => rgba(getComputedStyle(u).backgroundColor)[3] * faint(u) > 0.002;
  const edged = (u) => { const o = getComputedStyle(u); return px(o.borderTopWidth) > 0 && o.borderTopStyle !== 'none' && rgba(o.borderTopColor)[3] > 0.002; };
  const field = 'input, textarea, select, [contenteditable]:not([contenteditable="false"])';
  const shows = (u) => pictured(u) || /^(svg|img)$/i.test(u.tagName) || u.matches(field) || [...u.childNodes].some((n) => n.nodeType === 3 && n.data.trim());
  // Whether something over `el` at that point (not in it) draws there: a scrim, a bar's glass, a panel.
  const covered = (stack, at, el) => stack.slice(0, at).some((u) => !el.contains(u) && !u.contains(el)
    && (pictured(u) || grounded(u) || getComputedStyle(u).backdropFilter !== 'none'));
  // Whether `el` is a ground for what is drawn over it there: words, an icon or a picture (a choice's thumb under its
  // words), or a ground of what is in it over its middle (a ring round a dot).
  const under = (stack, at, el) => stack.slice(0, at).some((u) => (!el.contains(u) && shows(u)) || (u !== el && el.contains(u) && (grounded(u) || edged(u))));
  const onScreen = (x, y) => x >= 0 && y >= 0 && x < innerWidth && y < innerHeight;
  // Hit-testing asked for what is drawn: what takes no pointer is drawn too. What loops at its start meanwhile (a
  // placeholder's breath whole), as it was after.
  const every = document.createElement('style');
  every.textContent = '* { pointer-events: auto !important; }';
  document.head.append(every);
  const loops = document.getAnimations().filter((a) => a.effect?.getTiming().iterations === Infinity).map((a) => ({ a, at: a.currentTime, running: a.playState === 'running' }));
  for (const l of loops) { l.a.pause(); l.a.currentTime = 0; }
  // (what loops paused meanwhile: what still runs ends: on its way)
  const moving = (el) => { for (let n = el; n; n = n.parentElement) if (n.getAnimations().some((a) => a.playState === 'running')) return true; return false; };
  let measured = 0;
  try {
    for (const el of document.querySelectorAll('body *')) {
      const cs = getComputedStyle(el);
      if (cs.visibility !== 'visible' || cs.display === 'none' || el.closest('[data-depicts]')) continue;
      const b = el.getBoundingClientRect();
      if (b.width < 1 || b.height < 1) continue;
      if (el.closest('svg')) continue;
      // What dims the whole page (a dialog's scrim) is no mark, nor a blot blurred to no edge (a picture's colours drifting
      // while it comes).
      if (b.width >= innerWidth * 0.9 && b.height >= innerHeight * 0.9) continue;
      if (/blur\(/.test(cs.filter)) continue;
      const empty = !el.textContent.trim() && !el.matches(field) && !el.querySelector(`img, svg, video, canvas, iframe, ${field}`) && !pictured(el);
      if (!empty) continue;
      const x = b.left + b.width / 2, y = b.top + b.height / 2;
      if (!onScreen(x, y) || el.closest(':disabled, [aria-disabled="true"]')) continue;
      const stack = document.elementsFromPoint(x, y);
      const at = stack.indexOf(el);
      if (at < 0 || stack.slice(at).some(moving) || covered(stack, at, el) || under(stack, at, el)) continue;
      const g = ground(stack, at);
      if (!g) continue;
      // Seen by its ground or by its edge (a box to tick, white with a line round it), whichever stands further off what
      // it lies on; in the colour of a ground under it, cut out of that.
      let best = null;
      const look = (what, ink, gx) => {
        if (!gx) return;
        const [r, g, bl, a] = rgba(ink);
        const o = a * faint(el);
        if (o <= 0.002) return;
        const shown = laid(gx.c, [r, g, bl], o);
        if (same(shown, gx.c) || (o >= 0.999 && gx.beneath.some((u) => same(u, [r, g, bl])))) return;
        const k = ratio(shown, gx.c);
        if (!best || k > best.k) best = { k, said: `${name(el)}: ${what} ${Math.round(b.width)}x${Math.round(b.height)} ${hex(shown)} on ${hex(gx.c)}: ${k.toFixed(2)}:1, under ${MARK}` };
      };
      look('mark', cs.backgroundColor, g);
      // (each side it draws, at its middle: a spinner's arc is seen though its track is not)
      for (const side of ['Left', 'Top', 'Right', 'Bottom']) {
        const w = px(cs[`border${side}Width`]);
        if (w <= 0 || cs[`border${side}Style`] === 'none') continue;
        const ex = side === 'Left' ? b.left + w / 2 : side === 'Right' ? b.right - w / 2 : x;
        const ey = side === 'Top' ? b.top + w / 2 : side === 'Bottom' ? b.bottom - w / 2 : y;
        const edgeStack = document.elementsFromPoint(ex, ey);
        const edgeAt = edgeStack.indexOf(el);
        if (edgeAt >= 0 && !covered(edgeStack, edgeAt, el)) look('edge', cs[`border${side}Color`], ground(edgeStack, edgeAt));
      }
      if (!best) continue;
      measured++;
      if (best.k < MARK - 0.005) say(el, best.said);
    }
  } finally {
    every.remove();
    for (const l of loops) { l.a.currentTime = l.at; if (l.running) l.a.play(); }
  }
  return { measured, wrong };
}

/**
 * How the page is drawn, element by element, as far as it shows (on the screen, not cut away by what it is in, not
 * hidden, not faded to nothing): where, how big, how faint, its transform, its colours and outline. What a story is in
 * with motion and with motion reduced, to be the same (motion reduced is the same page, its motion taking no time:
 * web/ui/src/motion.ts). With it, the paths of what loops (an infinite animation on it or its pseudo-elements): it
 * rests still with motion reduced, as it should, and is left out of the comparison with what is in it.
 */
export function drawn() {
  const path = (el) => {
    const parts = [];
    for (let n = el; n && n !== document.body; n = n.parentElement) parts.unshift(`${n.tagName.toLowerCase()}${[...n.parentElement.children].indexOf(n)}`);
    return parts.join('>');
  };
  const looping = new Set();
  for (const a of document.getAnimations()) {
    const target = a.effect?.target;
    if (target && a.effect.getTiming().iterations === Infinity) looping.add(path(target));
  }
  // The spokes loop too, stepped by the page's clock rather than an animation (web/ui/src/motion.ts stepSpokes).
  for (const el of document.querySelectorAll('[data-tone="busy"], [data-badge="run"], [data-spokes]')) looping.add(path(el));
  // A scale's or a colour's share to a hundredth, a length to a pixel.
  const round = (v) => v.replace(/-?\d+\.\d+/g, (n) => String(Math.abs(Number(n)) < 2 ? Math.round(Number(n) * 100) / 100 : Math.round(Number(n))));
  const lines = [];
  // `clip`: what shows of the page through what it is in; `faint`: how faint what it is in has made it.
  const walk = (el, clip, faint) => {
    const s = getComputedStyle(el);
    if (s.display === 'none') return;
    const opacity = faint * Number(s.opacity);
    if (opacity < 0.01) return;
    const r = el.getBoundingClientRect();
    const shown = { left: Math.max(clip.left, r.left), top: Math.max(clip.top, r.top), right: Math.min(clip.right, r.right), bottom: Math.min(clip.bottom, r.bottom) };
    const at = path(el);
    if (s.visibility === 'visible' && shown.right - shown.left >= 1 && shown.bottom - shown.top >= 1) {
      lines.push(`${at} ${Math.round(shown.left)},${Math.round(shown.top)} ${Math.round(shown.right - shown.left)}x${Math.round(shown.bottom - shown.top)} opacity ${opacity.toFixed(2)} ` +
        `transform ${round(s.transform)} ground ${s.backgroundColor} text ${s.color} outline ${s.outlineStyle}`);
    }
    const inner = s.overflowX === 'visible' && s.overflowY === 'visible' && s.clipPath === 'none' ? clip
      : { left: Math.max(clip.left, r.left), top: Math.max(clip.top, r.top), right: Math.min(clip.right, r.right), bottom: Math.min(clip.bottom, r.bottom) };
    for (const child of el.children) walk(child, inner, opacity);
  };
  const screen = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
  for (const child of document.body.children) walk(child, screen, 1);
  return { lines, loops: [...looping] };
}
