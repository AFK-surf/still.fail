// What the stories are measured by (docs/ui-panels.md; test/browser/stories.mjs runs them in each story's page): each
// a function run in the page, returning what it measured and what is off. Told to `mark`, each also marks what is off
// (data-off, saying why), as the web app's development build does as it runs (web/src/dev/offs.ts).

/**
 * Every corner: each rounded thing with a ground of its own or to press, standing in a corner of the rounded box drawn
 * round it, is as far from both edges of that corner and rounded as the box less that distance (concentric).
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
    // A slider's knob goes where the value is: not set in a corner.
    if (el.closest('[role=slider]')) continue;
    const pressed = el.matches('button, a[href], [role=button], [role=menuitem], [role=menuitemradio], [role=menuitemcheckbox], [role=option], [role=tab], input, textarea, select, summary');
    if (!drawn(cs) && !pressed) continue;
    const b = el.getBoundingClientRect();
    if (b.width < 8 || b.height < 8) continue;
    // The rounded box drawn round it.
    let box = el.parentElement, bs = null;
    while (box && box !== document.body) {
      bs = getComputedStyle(box);
      if (radius(bs) >= 0.5 && drawn(bs)) break;
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
    for (const [where, g1, g2, prop] of corners) {
      // Its corner as drawn (no more than half its side), and what stands in it: within a little over half of that from
      // both edges (further in, it is beside the corner, not in it).
      const rbc = Math.min(px(bs[prop]), c.width / 2, c.height / 2);
      if (rbc < 0.5 || g1 > rbc * 0.6 || g2 > rbc * 0.6) continue;
      measured++;
      const who = `${name(box)} › ${name(el)} (${where})`;
      if (Math.abs(g1 - g2) > 1) { say(el, `${who}: ${g1.toFixed(1)} from the side, ${g2.toFixed(1)} from the ${where.split(' ')[0]}`); continue; }
      const own = Math.min(px(cs[prop]), r.height / 2, r.width / 2), want = Math.min(Math.max(rbc - g1, 0), r.height / 2, r.width / 2);
      if (Math.abs(own - want) > 1) say(el, `${who}: rounded ${own.toFixed(1)}, ${g1.toFixed(1)} in from a corner of ${rbc.toFixed(1)} (wants ${want.toFixed(1)})`);
    }
  }
  return { measured, wrong };
}

/**
 * Every small panel (a surface saying its --panel-pad): its corner its inner one and its padding together; padded 6
 * (all but ⌘K, a dialog); a panel of words' blocks in by 10 and as far from its top and foot; its rows' words in by 10;
 * what sits in its corners as far from both edges and concentric.
 */
export function panels(mark = false) {
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
        const side = gl <= near ? gl : gr <= near ? gr : null, end = gt <= near ? gt : gb <= near ? gb : null;
        if (side === null || end === null || side < -0.5 || end < -0.5) continue;
        corners++;
        const who = `${name} › ${d.className.toString().split(' ')[0] || d.tagName}`;
        if (Math.abs(side - end) > 0.75) say(d, `${who}: ${side.toFixed(1)} from the side, ${end.toFixed(1)} from the top or foot`);
        else if (Math.abs(Math.min(dr, r.height / 2, r.width / 2) - Math.min(outer - side, r.height / 2, r.width / 2)) > 0.75) say(d, `${who}: corner ${dr} ${side.toFixed(1)} in from a corner of ${outer}`);
      }
    }
    return { surfaces, corners, wrong };
}
