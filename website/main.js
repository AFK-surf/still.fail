// monoid · official site. No framework, no dependencies: everything here runs after the page has painted (defer).
(() => {
  "use strict";
  const root = document.documentElement;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private window */ } },
  };

  const nav = $("#nav");
  const sheet = $("#nav-list", nav);
  const ind = $(".nav-ind", nav);

  // ---- Language: both are in the page, one is shown ----
  // Labels read by screen readers follow too: an element keeps its Chinese label in aria-label and its English one in
  // data-aria-en.
  for (const el of $$("[data-aria-en]")) el.dataset.ariaZh = el.getAttribute("aria-label") || "";
  function setLang(l, remember) {
    root.dataset.lang = l;
    root.lang = l === "en" ? "en" : "zh-CN";
    for (const b of $$("[data-set-lang]")) b.setAttribute("aria-pressed", String(b.dataset.setLang === l));
    for (const a of $$("[data-legal]")) a.href = (l === "en" ? "/en" : "") + new URL(a.href).pathname.replace(/^\/en/, "");
    for (const el of $$("[data-aria-en]")) el.setAttribute("aria-label", l === "en" ? el.dataset.ariaEn : el.dataset.ariaZh);
    if (remember) store.set("monoid.site.lang", l);
    placeInd(false); // the labels changed width
  }
  for (const b of $$("[data-set-lang]")) b.addEventListener("click", () => setLang(b.dataset.setLang, true));

  // ---- The bar: its lower edge fades the page out only once something has scrolled under it ----
  let under = false;
  const edge = () => { const s = scrollY > 1; if (s !== under) { under = s; nav.toggleAttribute("data-scrolled", s); } };
  addEventListener("scroll", edge, { passive: true });
  edge();

  // ---- Mobile menu: a sheet from under the bar. Escape or the dimmed page closes it; Tab stays inside while open ----
  const menu = $(".menu-btn", nav);
  const narrow = matchMedia("(max-width: 980px)");
  const isOpen = () => nav.hasAttribute("data-open");
  function setMenu(open, refocus) {
    if (open === isOpen()) return;
    nav.toggleAttribute("data-open", open);
    root.classList.toggle("menu-open", open);
    menu.setAttribute("aria-expanded", String(open));
    if (open) $("a", sheet).focus({ preventScroll: true });
    else if (refocus) menu.focus({ preventScroll: true });
  }
  menu.addEventListener("click", () => setMenu(!isOpen(), true));
  $(".nav-scrim", nav).addEventListener("click", () => setMenu(false, true));
  for (const a of $$("a", sheet)) a.addEventListener("click", () => setMenu(false, false));
  narrow.addEventListener("change", () => setMenu(false, false));
  document.addEventListener("keydown", (e) => {
    if (!isOpen()) return;
    if (e.key === "Escape") { e.preventDefault(); setMenu(false, true); return; }
    if (e.key !== "Tab") return;
    const stops = $$("a[href], button", nav).filter((el) => el.getClientRects().length);
    const first = stops[0], last = stops[stops.length - 1];
    if (!nav.contains(document.activeElement)) { e.preventDefault(); first.focus(); }
    else if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });

  // ---- Links within the page land where they point ----
  // Bands below the fold are laid out only as they come near (content-visibility), so their heights settle during a
  // long smooth scroll and it would stop short (and the devices scene would snap it). So a far jump goes most of the
  // way at once, lets the bands near the target settle, then glides the last stretch, and checks where it landed.
  const targetY = (t) => t.id === "top" ? 0 : t.getBoundingClientRect().top + scrollY - (parseFloat(getComputedStyle(t).scrollMarginTop) || 0);
  const frames = (n) => new Promise((ok) => { const f = () => (n-- ? requestAnimationFrame(f) : ok()); f(); });
  const settle = () => new Promise((ok) => {
    let done = false;
    const end = () => { if (!done) { done = true; removeEventListener("scrollend", end); ok(); } };
    addEventListener("scrollend", end);
    setTimeout(end, 900);
  });
  async function go(t) {
    const far = Math.abs(targetY(t) - scrollY) > innerHeight * 1.5;
    if (reduce || far) {
      const y = targetY(t);
      scrollTo({ top: reduce ? y : y - Math.sign(y - scrollY) * innerHeight * 0.6, behavior: "instant" });
      await frames(2);
    }
    if (!reduce) { scrollTo({ top: targetY(t), behavior: "smooth" }); await settle(); }
    for (let i = 0; i < 4 && Math.abs(targetY(t) - scrollY) > 2; i++) { scrollTo({ top: targetY(t), behavior: "instant" }); await frames(2); }
  }
  document.addEventListener("click", (e) => {
    const a = e.target.closest?.('a[href^="#"]');
    if (!a || e.defaultPrevented || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const id = decodeURIComponent(a.hash.slice(1));
    const t = id && document.getElementById(id);
    if (!t) return;
    e.preventDefault();
    if (isOpen()) setMenu(false, false);
    history.pushState(null, "", id === "top" ? location.pathname + location.search : "#" + id);
    go(t);
    // Keyboard users continue from the section they jumped to.
    if (!t.matches("a, button, input, [tabindex]")) t.setAttribute("tabindex", "-1");
    t.focus({ preventScroll: true });
  });
  if (location.hash.length > 3) {
    const t = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (t) addEventListener("load", () => frames(2).then(() => go(t)), { once: true });
  }

  // ---- Which section is on screen: its link is marked, and one indicator slides under it ----
  // A thin stripe across the middle of the screen decides; a band with no link (the hero, the overview) clears it.
  const links = new Map($$('a[href^="#"]', sheet).map((a) => [a.hash.slice(1), a]));
  let current = null;
  function placeInd(slide) {
    if (!current || !current.offsetWidth) { ind.removeAttribute("data-on"); return; }
    // Coming from nowhere, it appears in place; from another link, it slides.
    ind.toggleAttribute("data-jump", !slide || !ind.hasAttribute("data-on"));
    ind.style.setProperty("--x", current.offsetLeft + "px");
    ind.style.setProperty("--w", current.offsetWidth);
    ind.setAttribute("data-on", "");
  }
  function mark(a) {
    if (a === current) return;
    current?.removeAttribute("aria-current");
    current = a || null;
    current?.setAttribute("aria-current", "true");
    placeInd(true);
  }
  const seen = new Map();
  const spy = new IntersectionObserver((entries) => {
    for (const e of entries) seen.set(e.target, e.isIntersecting);
    let on = null;
    for (const [s, hit] of seen) if (hit) on = s;
    mark(on && links.get(on.id));
  }, { rootMargin: "-45% 0px -50% 0px" });
  for (const s of $$("main > section")) spy.observe(s);
  new ResizeObserver(() => placeInd(false)).observe(sheet);
  document.fonts?.ready.then(() => placeInd(false));
  setLang(root.dataset.lang === "en" ? "en" : "zh", false);

  // ---- Tabs (the product overview and the devices) ----
  // data-tabs: panels are shown and hidden ([hidden]). data-tabs="stack" (the overview): the panels sit on top of one
  // another and the active one is marked [data-on] (the others inert), so CSS can cross-fade them; each picture keeps
  // its place in the list's order (earlier ones above, later ones below), so a switch moves the way the list does.
  for (const group of $$("[data-tabs]")) {
    // Real tabs (role=tab) keep one tab stop and arrow keys; the overview's accordion buttons (data-tab) are each a stop.
    const tabs = $$('[role="tab"], [data-tab]', group);
    const stack = group.dataset.tabs === "stack";
    const select = (tab, focus) => {
      for (const t of tabs) {
        const on = t === tab;
        if (t.hasAttribute("data-tab")) t.setAttribute("aria-expanded", String(on));
        else { t.setAttribute("aria-selected", String(on)); t.tabIndex = on ? 0 : -1; }
        t.closest(".ov-item")?.toggleAttribute("data-on", on);
        const panel = document.getElementById(t.getAttribute("aria-controls"));
        if (!panel) continue;
        if (stack) { panel.toggleAttribute("data-on", on); panel.inert = !on; } else panel.hidden = !on;
      }
      if (focus) tab.focus();
    };
    const pick = (i, focus) => select(tabs[i], focus);
    if (stack) {
      // The overview turns to its next item on its own while nobody is using it, so a reader who only scrolls sees all
      // three pictures. The active item's top rule fills as its timer (a CSS animation, so pausing is exact and costs
      // no script); its end turns the page. It runs only on wide screens (on narrow ones the text above the picture
      // would push it about), while at least half of it is on screen and the tab is visible; it pauses while the
      // pointer or the focus is inside, and stops for good once the reader picks an item. Never with reduced motion.
      const wide = matchMedia("(min-width: 961px)");
      let stopped = reduce, seen = false, inside = false;
      const sync = () => {
        const auto = !stopped && wide.matches;
        group.toggleAttribute("data-auto", auto);
        group.toggleAttribute("data-run", auto && seen && !inside && !document.hidden);
      };
      new IntersectionObserver(([e]) => {
        seen = e.intersectionRatio >= 0.5;
        group.classList.toggle("play", e.isIntersecting); // the pictures' own loops run only while on screen
        sync();
      }, { threshold: [0, 0.5] }).observe(group);
      const hold = () => { inside = group.matches(":hover") || group.contains(document.activeElement); sync(); };
      for (const ev of ["pointerenter", "pointerleave", "focusin", "focusout"]) group.addEventListener(ev, () => setTimeout(hold));
      document.addEventListener("visibilitychange", sync);
      wide.addEventListener("change", sync);
      group.addEventListener("animationend", (e) => {
        if (e.animationName !== "ov-dwell" || stopped) return;
        const i = tabs.findIndex((t) => t.getAttribute("aria-expanded") === "true");
        pick((i + 1) % tabs.length);
      });
      tabs.forEach((t) => t.addEventListener("click", () => { stopped = true; sync(); }));
      sync();

      // Phones: the overview is a swiper, one card per item (30-overview.css). The browser owns the gesture and its
      // momentum; the script only follows it. The card at the snap line is the active item (its event lands, its loops
      // run), the dots' pill tracks the scroll (a custom property, once a frame while scrolling), and an item's name or
      // a dot scrolls its card in.
      const car = matchMedia("(max-width: 760px) and (min-height: 501px)"); // the same query as the CSS
      const nav = group.nextElementSibling?.classList.contains("ov-nav") ? group.nextElementSibling : null;
      const dots = nav ? $$("button", nav) : [], pill = nav && $(".ov-pill", nav);
      const panes = tabs.map((t) => document.getElementById(t.getAttribute("aria-controls")));
      const at = () => Math.max(0, tabs.findIndex((t) => t.getAttribute("aria-expanded") === "true"));
      const slide = (i, smooth = true) => {
        const pad = parseFloat(getComputedStyle(group).scrollPaddingLeft) || 0;
        const x = group.scrollLeft + panes[i].getBoundingClientRect().left - group.getBoundingClientRect().left - pad;
        group.scrollTo({ left: x, behavior: smooth && !reduce ? "smooth" : "auto" });
      };
      let frame = 0;
      const follow = () => {
        frame = 0;
        if (!car.matches) return;
        // The last card cannot reach the snap line (the row ends), so position is read against the full scroll range.
        const max = group.scrollWidth - group.clientWidth;
        const p = max > 0 ? Math.min(1, Math.max(0, group.scrollLeft / max)) * (tabs.length - 1) : 0;
        pill?.style.setProperty("--p", p.toFixed(3));
        const i = Math.round(p);
        if (i !== at()) pick(i);
      };
      group.addEventListener("scroll", () => { frame ||= requestAnimationFrame(follow); }, { passive: true });
      tabs.forEach((t, i) => t.addEventListener("click", () => { if (car.matches) slide(i); }));
      dots.forEach((d, i) => d.addEventListener("click", () => slide(i)));
      // Turning into a swiper (a phone rotated back upright), it opens on the item that was active.
      car.addEventListener("change", () => { if (car.matches) { slide(at(), false); follow(); } });
    }
    tabs.forEach((t, i) => {
      t.addEventListener("click", () => pick(i));
      if (t.hasAttribute("data-tab")) return;
      t.tabIndex = t.getAttribute("aria-selected") === "true" ? 0 : -1;
      t.addEventListener("keydown", (e) => {
        const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
        if (step) { e.preventDefault(); pick((i + step + tabs.length) % tabs.length, true); }
        if (e.key === "Home") { e.preventDefault(); pick(0, true); }
        if (e.key === "End") { e.preventDefault(); pick(tabs.length - 1, true); }
      });
    });
  }

  // ---- Every device, as a swiper (wherever the scene below does not play) ----
  // The track is native scroll with snapping, so the browser owns the gesture and its momentum; the script only
  // follows it. The dots' pill tracks the scroll position continuously (a transform, once a frame while scrolling);
  // the card in view is marked [data-on] (its picture's loops run, the others pause), and the dots and arrows jump.
  {
    const swipe = $(".dv-swipe"), track = $("#dv-track"), cards = $$(".fpanel", track);
    const dots = $$(".dv-dots button", swipe), pill = $(".dv-pill", swipe), count = $(".dv-count b", swipe);
    const [prev, next] = $$(".dv-arrows button", swipe);
    let on = -1, frame = 0;
    const left = (card) => card.offsetLeft - track.offsetLeft - parseFloat(getComputedStyle(track).scrollPaddingLeft || 0);
    const go = (i) => track.scrollTo({ left: left(cards[Math.max(0, Math.min(cards.length - 1, i))]), behavior: reduce ? "auto" : "smooth" });
    const follow = () => {
      frame = 0;
      // The last card cannot reach the snap line (the track ends), so position is read against the scroll's full range.
      const max = track.scrollWidth - track.clientWidth;
      const p = max > 0 ? Math.max(0, Math.min(1, track.scrollLeft / max)) * (cards.length - 1) : 0;
      pill.style.setProperty("--p", p.toFixed(3));
      const i = Math.round(p);
      if (i === on) return;
      on = i;
      cards.forEach((c, k) => c.toggleAttribute("data-on", k === i));
      dots.forEach((d, k) => d.toggleAttribute("aria-current", k === i));
      count.textContent = String(i + 1).padStart(2, "0");
      prev.disabled = i === 0;
      next.disabled = i === cards.length - 1;
    };
    track.addEventListener("scroll", () => { frame ||= requestAnimationFrame(follow); }, { passive: true });
    dots.forEach((d, k) => d.addEventListener("click", () => go(k)));
    for (const b of [prev, next]) b.addEventListener("click", () => go(on + Number(b.dataset.step)));
    track.addEventListener("keydown", (e) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (step && e.target === track) { e.preventDefault(); go(on + step); }
    });
    new IntersectionObserver(([e]) => swipe.classList.toggle("play", e.isIntersecting)).observe(swipe);
    new ResizeObserver(follow).observe(track);
    follow();
  }

  // ---- Every device, as one scene played by scrolling (large screens with motion allowed: html.scrolly, set in the head) ----
  // The stage stays on screen with CSS (position: sticky in a tall track, sized from the first paint, so nothing moves
  // when the script arrives); GSAP's ScrollTrigger scrubs one timeline through it. The same conversation travels across
  // the screens: the Duo folded with a notification, then unfolding on its hinge; Android flying in, linked to it; the
  // camera pulling back to the desktop window with the phones on its edges; the window becoming the web app; Slack coming
  // in, the band turning Ink, and every screen marked Done at once. GSAP is fetched only as the section comes near.
  const loadScript = (src) => new Promise((ok, fail) => {
    const s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = fail;
    document.head.appendChild(s);
  });
  function initScrolly() {
    const { gsap, ScrollTrigger } = window;
    gsap.registerPlugin(ScrollTrigger);
    const show = $(".dv-show"), stage = $(".dv-stage", show), view = $(".dv-view", show), scene = $(".dv-scene", show);
    const steps = $$(".dv-step", show), rail = $$(".dv-rail li", show), tags = $$(".dv-tags .mtag", show);
    const duoBox = $(".d-duo", scene), duo = $(".duo", duoBox), [inner] = duo.children, coverNote = $(".cover-notif", duoBox);
    const droid = $(".d-android", scene), laptop = $(".d-laptop", scene), slack = $(".d-slack", scene);
    const L = (n) => $(`.dv-links .l${n}`, scene);
    const navH = () => $("#nav").offsetHeight;

    // The scene is drawn at 900 × 720 and scaled to fit what is left of the stage beside the words, with a margin so no
    // device ever touches the stage's edge.
    const fit = () => scene.style.setProperty("--k", Math.min((view.clientWidth - 72) / 900, (view.clientHeight - 96) / 720, 1.15).toFixed(3));
    fit();
    ScrollTrigger.addEventListener("refreshInit", fit);

    /** Places a device's centre at (x, y) of the scene, at `scale`. */
    const at = (x, y, scale = 1, more = {}) => ({ x, y, xPercent: -50, yPercent: -50, scale, ...more });
    gsap.set(duoBox, at(450, 360, 1.08));
    gsap.set(droid, at(760, 900, 1, { rotation: 14, autoAlpha: 0 }));
    gsap.set(laptop, at(450, 300, 0.78, { autoAlpha: 0 }));
    gsap.set(slack, at(980, 120, 0.9, { autoAlpha: 0 }));
    // Folded: only the cover screen shows; the inner one is turned away behind the hinge.
    gsap.set(duo, { clipPath: "inset(0% 0% 0% 50% round 30px)", xPercent: -25 });
    gsap.set(inner, { rotationY: 100, transformOrigin: "100% 50%", transformPerspective: 1000, autoAlpha: 0 });
    gsap.set(coverNote, { y: -30, autoAlpha: 0 });
    gsap.set(steps.slice(1), { autoAlpha: 0, y: 24 });

    const tl = gsap.timeline({ defaults: { ease: "power2.inOut", duration: 1 } });
    const labels = [];
    const stop = (name) => { tl.addLabel(name); labels.push(name); };
    /** The words, the step number, the rail and the tag move to step `i`, starting at `t`. */
    const words = (i, t) => {
      tl.to(steps[i - 1], { autoAlpha: 0, y: -24, duration: 0.4 }, t)
        .fromTo(steps[i], { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: 0.5, immediateRender: false }, t + 0.3)
        .to(tags[i - 1], { autoAlpha: 0, duration: 0.25 }, t)
        .fromTo(tags[i], { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.25, immediateRender: false }, t + 0.45);
    };

    // 0 · Folded: a notification lands on the cover screen (the first stop shows it landed).
    tl.to(coverNote, { y: 0, autoAlpha: 1, duration: 0.4, ease: "back.out(1.7)" }, 0.05);
    stop("closed");
    tl.to({}, { duration: 0.4 });
    // 1 · It unfolds: the inner screen swings open on the hinge and the device grows to both halves.
    let t = tl.duration();
    words(1, t);
    tl.to(coverNote, { autoAlpha: 0, y: -16, duration: 0.3 }, t)
      .to(duo, { clipPath: "inset(0% 0% 0% 0% round 30px)", xPercent: 0, duration: 1 }, t + 0.1)
      .to(inner, { rotationY: 0, autoAlpha: 1, duration: 1 }, t + 0.1)
      .to(duoBox, { rotation: -2, duration: 1 }, t + 0.1);
    stop("open");
    tl.to({}, { duration: 0.4 });
    // 2 · Android flies in; a line ties the two screens to the same chat.
    t = tl.duration();
    words(2, t);
    tl.to(duoBox, { ...at(310, 330, 0.8), rotation: 0, duration: 1 }, t)
      .to(droid, { ...at(705, 375, 1), rotation: 0, autoAlpha: 1, duration: 1, ease: "power3.out" }, t + 0.15)
      .fromTo($(".notif", droid), { y: -40, autoAlpha: 0 }, { y: 0, autoAlpha: 1, duration: 0.35, ease: "back.out(1.6)", immediateRender: true }, t + 0.9)
      .to(L(1), { strokeDashoffset: 0, duration: 0.5 }, t + 0.85);
    stop("android");
    tl.to({}, { duration: 0.4 });
    // 3 · The camera pulls back: the desktop window rises behind, the phones settle on its edges, the load bars fill.
    t = tl.duration();
    words(3, t);
    tl.to(L(1), { autoAlpha: 0, duration: 0.3 }, t)
      // The phones sit over the window's corners, never its content (the VI's "two devices, one event").
      .to(duoBox, { ...at(205, 480, 0.5), duration: 1 }, t)
      .to(droid, { ...at(762, 430, 0.62), duration: 1 }, t)
      .to(laptop, { ...at(450, 300, 0.92), autoAlpha: 1, duration: 1, ease: "power3.out" }, t + 0.1)
      .fromTo($$(".body-desk .meter i", laptop), { scaleX: 0 }, { scaleX: 1, transformOrigin: "0% 50%", stagger: 0.08, duration: 0.5, immediateRender: true }, t + 0.7);
    stop("desktop");
    tl.to({}, { duration: 0.4 });
    // 4 · The window becomes the web app: an address bar slides in, the same chat appears in it.
    t = tl.duration();
    words(4, t);
    tl.fromTo($(".t-url", laptop), { autoAlpha: 0, scaleX: 0.2, transformOrigin: "0% 50%" }, { autoAlpha: 1, scaleX: 1, duration: 0.6, immediateRender: true }, t)
      .to($(".t-desk", laptop), { autoAlpha: 0, duration: 0.2 }, t)
      .to($(".body-desk", laptop), { autoAlpha: 0, y: -12, duration: 0.4 }, t + 0.2)
      .fromTo($(".body-web", laptop), { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.3, immediateRender: true }, t + 0.4)
      .fromTo($$(".body-web > *", laptop), { y: 14, autoAlpha: 0 }, { y: 0, autoAlpha: 1, stagger: 0.15, duration: 0.4, immediateRender: true }, t + 0.45);
    stop("web");
    tl.to({}, { duration: 0.4 });
    // 5 · Slack comes in; the band turns Ink; lines run from the thread to every screen, and each is marked Done.
    t = tl.duration();
    words(5, t);
    tl.to($(".dv-ink", stage), { opacity: 1, duration: 0.7 }, t)
      .to(stage, { "--dv-fg": "#FFFFFF", "--dv-mut": "#C9CACD", duration: 0.7 }, t)
      .to(laptop, { ...at(400, 330, 0.84), duration: 0.9 }, t)
      .to(droid, { ...at(705, 455, 0.62), duration: 0.9 }, t)
      .to(slack, { ...at(705, 128, 0.9), autoAlpha: 1, duration: 0.9, ease: "power3.out" }, t + 0.1)
      .fromTo($$(".slack .msg", slack), { x: -14, autoAlpha: 0 }, { x: 0, autoAlpha: 1, stagger: 0.18, duration: 0.4, immediateRender: true }, t + 0.5)
      .to([L(2), L(3), L(4)], { strokeDashoffset: 0, stagger: 0.1, duration: 0.5 }, t + 0.9)
      .to([$(".done", laptop), $(".done", duoBox), $(".done", droid)], { scale: 1, stagger: 0.12, duration: 0.35, ease: "back.out(2)" }, t + 1.25);
    stop("slack");
    tl.to({}, { duration: 0.5 });

    const pos = (name) => tl.labels[name] / tl.duration();
    const no = $(".dv-no b", show), bar = $(".dv-bar i", show);
    const railOf = [0, 0, 1, 2, 3, 4];
    let current = -1;
    const mark = (i) => {
      if (i === current) return;
      current = i;
      no.textContent = String(i + 1).padStart(2, "0");
      rail.forEach((li, k) => li.toggleAttribute("data-on", k === railOf[i]));
      steps.forEach((s, k) => s.setAttribute("aria-hidden", String(k !== i)));
    };
    const st = ScrollTrigger.create({
      trigger: show,
      start: () => `top top+=${navH() + 16}`,
      end: () => `bottom top+=${navH() + 16 + stage.offsetHeight}`,
      animation: tl,
      scrub: 0.7,
      // Snap to the nearest step, not to where a flick would carry: no screen is skipped unseen.
      snap: { snapTo: labels.map(pos), inertia: false, duration: { min: 0.25, max: 0.7 }, delay: 0.12, ease: "power2.inOut" },
      invalidateOnRefresh: true,
      onUpdate(self) {
        bar.style.transform = `scaleX(${self.progress})`;
        const time = self.progress * tl.duration(); // where the scroll is, not where the scrub has got to
        let i = 0;
        labels.forEach((name, k) => { if (k && time >= tl.labels[labels[k - 1]] + (tl.labels[name] - tl.labels[labels[k - 1]]) * 0.5) i = k; });
        mark(i);
      },
    });
    mark(0);
    // The rail scrolls to its device.
    rail.forEach((li) => $("button", li).addEventListener("click", () => {
      const i = Number(li.dataset.i);
      scrollTo({ top: st.start + (st.end - st.start) * pos(labels[i]), behavior: "smooth" });
    }));
  }
  if (root.classList.contains("scrolly")) {
    // The scene, from its template, into its placeholder (which already has its height: nothing moves).
    $(".dv-show").append($("#dv-stage").content.cloneNode(true));
    let started = false;
    const start = () => {
      if (started) return;
      started = true;
      loadScript("assets/vendor/gsap.min.js")
        .then(() => loadScript("assets/vendor/ScrollTrigger.min.js"))
        .then(initScrolly)
        .catch(() => root.classList.remove("scrolly")); // without GSAP: the plain tabs
    };
    const near = new IntersectionObserver(([e]) => { if (e.isIntersecting) { near.disconnect(); start(); } }, { rootMargin: "1600px 0px" });
    near.observe($("#devices"));
    addEventListener("load", () => setTimeout(start, 2500), { once: true });
  }

  // ---- Reveal on scroll ----
  // Everything is visible at the first paint. Then only what starts below the fold is set to wait (.rv-wait), and it
  // comes in as it reaches the screen (.rv-in, removed again once done so the element's own transitions return).
  // Groups (.split-head, .head, [data-stagger]) bring their children in one after another, at most 6 steps.
  {
    const rvs = $$(".rv");
    const STAGGER = 60, DUR = 520;
    for (const g of rvs) if (g.matches(".split-head, .head, [data-stagger]")) [...g.children].forEach((c, i) => c.style.setProperty("--i", Math.min(i, 6)));
    const show = (el) => { el.classList.add("in"); };
    if (!("IntersectionObserver" in window)) rvs.forEach(show);
    else {
      const met = new WeakSet();
      const io = new IntersectionObserver((entries) => {
        for (const e of entries) {
          const el = e.target;
          if (!met.has(el)) {
            met.add(el);
            // Already on screen (or above it, after a jump to an anchor): leave it be. A band not yet laid out
            // (content-visibility) reports an empty box: it is far below.
            const r = e.boundingClientRect;
            if ((r.width || r.height) && r.top < innerHeight) { show(el); io.unobserve(el); continue; }
            el.classList.add("rv-wait");
          }
          if (!e.isIntersecting) continue;
          io.unobserve(el);
          el.classList.add("rv-in");
          el.classList.remove("rv-wait");
          show(el);
          const steps = el.matches(".split-head, .head, [data-stagger]") ? Math.min(el.children.length - 1, 6) : 0;
          setTimeout(() => el.classList.remove("rv-in"), DUR + steps * STAGGER + 80);
        }
      }, { rootMargin: "0px 0px -8% 0px" });
      rvs.forEach((el) => io.observe(el));
    }
  }

  // ---- The teams grid: each picture tells its story in steps, only while its cell is on screen ----
  // data-seq: how long each step holds (ms). An element with data-in="n" is .is-in from step n until its data-out
  // (else to the end); the cell carries data-step for the moves that depend on it. Step 0 is the rest that also clears
  // the last loop, so wrapping round plays the exits. CSS says how each thing enters and leaves (50-teams.css).
  // A list marked data-follow scrolls, as a chat does, to keep its newest message in view.
  // Reduced motion: the picture stands at its data-still step, the story told in one frame.
  const cells = $$("#teams .cell[data-seq]");
  for (const cell of cells) {
    const hold = cell.dataset.seq.split(" ").map(Number), parts = $$("[data-in]", cell), follow = $("[data-follow]", cell);
    let step = -1, timer = 0;
    const set = (s) => {
      step = s; cell.dataset.step = s;
      for (const p of parts) p.classList.toggle("is-in", s >= +p.dataset.in && s < +(p.dataset.out ?? hold.length));
      if (follow) {
        let end = 0;
        for (const p of parts) if (p.classList.contains("is-in") && follow.contains(p)) end = Math.max(end, p.offsetTop + p.offsetHeight);
        follow.style.transform = `translateY(${-Math.max(0, follow.offsetTop + end + 12 - follow.parentElement.clientHeight)}px)`;
      }
    };
    cell.show = set;
    const tick = () => { set((step + 1) % hold.length); timer = setTimeout(tick, hold[step]); };
    const still = +(cell.dataset.still ?? hold.length - 1);
    cell.play = (on) => {
      if (reduce) { if (on) set(still); return; } // laid out only now (content-visibility), so a list can follow
      cell.classList.toggle("play", on);
      if (!on) { clearTimeout(timer); timer = 0; } else if (!timer) timer = setTimeout(tick, hold[step] / 2);
    };
    set(reduce ? still : 0);
  }
  const play = new IntersectionObserver((entries) => { for (const e of entries) e.target.play(e.isIntersecting); }, { threshold: .35 });
  for (const c of cells) play.observe(c);
  // On a phone the grid is a swiper (native scroll, 50-teams.css). The script only follows it: the dots' pill tracks the
  // scroll once a frame while it moves, the count names the card at the snap line, and a dot or an arrow key jumps.
  {
    const track = $("#teams .cells"), dots = $$("#teams .tm-dots button"), pill = $("#teams .tm-pill"), count = $("#teams .tm-count b");
    let on = -1, frame = 0;
    const swiper = () => track.scrollWidth > track.clientWidth + 1;
    const go = (i) => {
      const c = cells[Math.max(0, Math.min(cells.length - 1, i))];
      track.scrollTo({ left: c.offsetLeft - track.offsetLeft - parseFloat(getComputedStyle(track).scrollPaddingLeft || 0), behavior: reduce ? "auto" : "smooth" });
    };
    const follow = () => {
      frame = 0;
      if (swiper()) track.tabIndex = 0; else track.removeAttribute("tabindex");
      const max = track.scrollWidth - track.clientWidth; // the last card cannot reach the snap line: read the full range
      const p = max > 1 ? Math.max(0, Math.min(1, track.scrollLeft / max)) * (cells.length - 1) : 0;
      pill.style.setProperty("--p", p.toFixed(3));
      const i = Math.round(p);
      if (i === on) return;
      on = i;
      dots.forEach((d, k) => d.toggleAttribute("aria-current", k === i));
      count.textContent = String(i + 1).padStart(2, "0");
    };
    track.addEventListener("scroll", () => { frame ||= requestAnimationFrame(follow); }, { passive: true });
    dots.forEach((d, k) => d.addEventListener("click", () => go(k)));
    track.addEventListener("keydown", (e) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (step && e.target === track && swiper()) { e.preventDefault(); go(on + step); }
    });
    new ResizeObserver(follow).observe(track);
    follow();
  }

  // ---- Copy the install command ----
  for (const b of $$("[data-copy]")) {
    b.addEventListener("click", async () => {
      const label = b.innerHTML;
      try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = root.dataset.lang === "en" ? "Copied" : "已复制"; }
      catch { b.textContent = root.dataset.lang === "en" ? "Select it" : "请手动复制"; }
      setTimeout(() => { b.innerHTML = label; }, 1400);
    });
  }

  // ---- Downloads: the one for this device first, in Blue ----
  const ua = navigator.userAgent;
  const platform = /Android/i.test(ua) ? "android"
    : /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? "ios"
    : /Macintosh/.test(ua) ? "mac" : /Windows/.test(ua) ? "windows" : /Linux|X11|CrOS/.test(ua) ? "web" : "mac";
  const mine = $(`#dl [data-for="${platform}"]`);
  if (mine) { mine.classList.add("primary"); mine.parentElement.prepend(mine); }

  // ---- The field: the mark taken apart ----
  // Each cell holds one of the mark's parts, an eye (a white dot) or a cheek (a peach pill), in diagonal runs of dot,
  // dot, pill. A ripple runs out from one cell and, as it reaches each cell, that cell turns to the next part of its
  // run: a dot closes to a pill, a pill opens to a dot. One ask, every device answering in turn. The ripple is an
  // explanation, so it takes its time to cross (about 3 s), but each cell's own change is a blink of about 250 ms.
  const EYE = [255, 255, 255], CHEEK = [246, 188, 159]; // the mark's own white and peach
  const DOT = .26, PILL_W = .44, PILL_H = .154; // in cells; the pill is the mark's cheek (.59 of an eye high), a little longer
  const SPEED = 9, BAND = 2.2, GAP = 3.4; // cells a second; cells over which one cell changes; seconds between ripples
  const part = (c, r, s) => ((c + 2 * r + s) % 3 === 2 ? 1 : 0); // 0 an eye, 1 a cheek
  const smooth = (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
  const pill = (p, x, y, pw, ph) => { // into a path or a context; a dot when pw = ph
    const r = ph / 2, dx = (pw - ph) / 2;
    p.moveTo(x - dx, y - r);
    p.arc(x + dx, y, r, -Math.PI / 2, Math.PI / 2);
    p.arc(x - dx, y, r, Math.PI / 2, Math.PI * 1.5);
    p.closePath();
  };

  function field(wrap, { loop, delay }) {
    const canvas = $("canvas", wrap), ctx = canvas.getContext("2d");
    const origin = $("[data-origin]", wrap);
    let w = 0, h = 0, cols = 24, cell = 0, rows = 0, oc = 0, or = 0, far = 0;
    // at: seconds into the ripple under way, or null between ripples; wait: seconds until the next one.
    let shift = 0, at = null, wait = loop ? delay : Infinity;
    let running = !reduce, inView = false, ready = false, raf = 0, timer = 0, last = 0, drawn = 0;
    const empty = new Set();
    function size() {
      w = canvas.clientWidth; h = canvas.clientHeight;
      if (!w || !h) return;
      cols = parseInt(getComputedStyle(wrap).getPropertyValue("--cols"), 10) || 24;
      cell = w / cols;
      rows = Math.max(1, Math.floor(h / cell + .01));
      const d = Math.min(devicePixelRatio || 1, 2);
      canvas.width = Math.round(w * d); canvas.height = Math.round(h * d);
      ctx.setTransform(d, 0, 0, d, 0, 0);
      measure();
      // Drawn: the hero fades the field in and brings its notes after it (CSS); until now the canvas was blank.
      canvas.dataset.drawn = "";
    }
    // The cells under each note's label and under the pause button are left empty, so they sit in a clean lane. The
    // ripple starts at the note marked data-origin, or, with none showing, in the middle of the top row.
    function measure() {
      if (!cell) return;
      empty.clear();
      const box = wrap.getBoundingClientRect();
      for (const el of $$(".ft-l, .fpause", wrap)) {
        const b = el.getBoundingClientRect();
        if (!b.width) continue;
        for (let r = Math.floor((b.top - box.top) / cell); r <= Math.floor((b.bottom - box.top - 1) / cell); r++)
          for (let c = Math.floor((b.left - box.left) / cell); c <= Math.floor((b.right - box.left - 1) / cell); c++) empty.add(r * cols + c);
      }
      if (origin?.offsetWidth) { oc = Math.round(origin.offsetLeft / cell); or = Math.round(origin.offsetTop / cell); }
      else { oc = (cols - 1) / 2; or = 0; }
      far = Math.max(Math.hypot(oc, or), Math.hypot(cols - 1 - oc, or), Math.hypot(oc, rows - 1 - or), Math.hypot(cols - 1 - oc, rows - 1 - or));
      draw();
    }
    if (origin) new ResizeObserver(() => measure()).observe($(".ft-l", origin)); // a label changes width with the language
    function draw() {
      ctx.clearRect(0, 0, w, h);
      const front = at === null ? -1 : at * SPEED;
      // As the ripple reaches a cell, the cell swells a little and settles (k: 0 before, 1 after) while it changes part.
      // Cells in one colour go into one path; only the few between colours are filled one by one.
      const still = [new Path2D(), new Path2D()];
      for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
        if (empty.has(r * cols + c)) continue;
        const a = part(c, r, shift), b = part(c, r, shift + 1);
        const k = front < 0 ? 0 : Math.min(1, Math.max(0, (front - Math.hypot(c - oc, r - or)) / BAND));
        const t = a + (b - a) * smooth(k), s = cell * (1 + .32 * Math.sin(Math.PI * k));
        const x = (c + .5) * cell, y = (r + .5) * cell;
        const pw = s * (DOT + (PILL_W - DOT) * t), ph = s * (DOT + (PILL_H - DOT) * t);
        if (t === 0 || t === 1) { pill(still[t], x, y, pw, ph); continue; }
        ctx.beginPath();
        pill(ctx, x, y, pw, ph);
        ctx.fillStyle = `rgb(${EYE.map((v, i) => Math.round(v + (CHEEK[i] - v) * t))})`;
        ctx.fill();
      }
      ctx.fillStyle = "#FFFFFF"; ctx.fill(still[0]);
      ctx.fillStyle = "#F6BC9F"; ctx.fill(still[1]);
    }
    // At most 30 frames a second, only while a ripple is under way; between ripples nothing runs but one timer.
    const active = () => running && inView && ready && !document.hidden;
    function tick(now) {
      raf = 0;
      if (!active()) { last = 0; return; }
      const dt = last ? Math.min((now - last) / 1000, .1) : 0;
      last = now;
      if (at === null) {
        if (wait === Infinity) { last = 0; return; }
        wait -= dt;
        if (wait > 0) { last = 0; timer = setTimeout(() => { timer = 0; wait = 0; start(); }, wait * 1000); return; }
        at = 0;
      } else at += dt;
      if (at * SPEED > far + BAND) { shift = (shift + 1) % 3; at = null; wait = loop ? GAP : Infinity; draw(); }
      else if (now - drawn >= 32) { drawn = now; draw(); }
      raf = requestAnimationFrame(tick);
    }
    const start = () => { if (active() && !raf && !timer) raf = requestAnimationFrame(tick); };
    // The field is drawn still at once; the first ripple waits for the page to load and the browser to be idle, so it
    // never competes with the first paint or the first tap.
    const go = () => { ready = true; start(); };
    const idle = () => ("requestIdleCallback" in window ? requestIdleCallback(go, { timeout: 2500 }) : setTimeout(go, 1200));
    if (running) document.readyState === "complete" ? idle() : addEventListener("load", idle, { once: true });
    new IntersectionObserver(([e]) => {
      // The closing band ripples once each time it comes on screen.
      if (e.isIntersecting && !inView && !loop && at === null) wait = delay;
      inView = e.isIntersecting; start();
    }, { threshold: .4 }).observe(wrap);
    document.addEventListener("visibilitychange", start);
    new ResizeObserver(size).observe(canvas);
    return {
      toggle() {
        running = !running; last = 0;
        if (running) start(); else { cancelAnimationFrame(raf); clearTimeout(timer); raf = timer = 0; }
        return running;
      },
    };
  }

  // Pause: the hero's field moves on its own, so it can be stopped. Under reduced motion it never moves, and the button
  // stays hidden. It is shown before the field is measured, so its cell is left empty.
  const pause = $("#pause");
  if (!reduce) pause.hidden = false;
  const hero = field($(".hero .field-wrap"), { loop: true, delay: 1.2 });
  field($(".band.end .field-wrap"), { loop: false, delay: .5 });
  pause.addEventListener("click", () => pause.setAttribute("aria-pressed", String(!hero.toggle())));
})();
