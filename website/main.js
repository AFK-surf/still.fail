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

    // The scene is drawn at 900 × 720 and scaled to fit what is left of the stage beside the words.
    const fit = () => scene.style.setProperty("--k", Math.min(view.clientWidth / 900, view.clientHeight / 720, 1.15).toFixed(3));
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
      .to(duoBox, { ...at(150, 505, 0.46), duration: 1 }, t)
      .to(droid, { ...at(808, 505, 0.62), duration: 1 }, t)
      .to(laptop, { ...at(450, 265, 0.92), autoAlpha: 1, duration: 1, ease: "power3.out" }, t + 0.1)
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
      .to(laptop, { ...at(395, 305, 0.84), duration: 0.9 }, t)
      .to(slack, { ...at(712, 122, 0.9), autoAlpha: 1, duration: 0.9, ease: "power3.out" }, t + 0.1)
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
      scrollTo({ top: st.start + (st.end - st.start) * pos(labels[i === 0 ? 1 : i]), behavior: "smooth" });
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

  // ---- The teams grid's pictures move only while they are on screen ----
  // The packets' lane is measured as its cell comes on screen (not before: the band is not laid out until then).
  const sizeLanes = (el) => { for (const l of $$(".lane", el)) l.style.setProperty("--lane", l.clientWidth + "px"); };
  if (!reduce) {
    const play = new IntersectionObserver((entries) => {
      for (const e of entries) { if (e.isIntersecting) sizeLanes(e.target); e.target.classList.toggle("play", e.isIntersecting); }
    }, { rootMargin: "60px" });
    for (const c of $$(".cell")) play.observe(c);
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

  // ---- The 168 Week (Comma VI): 24 hours across, 7 days down; each comma turns 15° an hour ----
  // Mon–Fri 9–18 are lit (45 cells): your hours at the desk. The other 123 are your stations working on.
  const COMMA = new Path2D("M27.5752 30.475C29.5842 26.9956 34.0342 25.803 37.5137 27.8119C40.8501 29.7385 42.081 33.9084 40.4053 37.3158C40.4099 37.3203 40.4144 37.3251 40.4189 37.3295C40.3568 37.4447 40.2857 37.5685 40.2051 37.6977C40.1952 37.715 40.1858 37.7331 40.1758 37.7504C39.7991 38.4028 39.3363 38.9749 38.8105 39.4604C37.1152 41.2376 34.3055 43.2112 30.4131 43.7602C30.2618 43.7814 30.1769 43.5981 30.29 43.4955C30.9997 42.8536 31.8303 42.0905 32.6543 41.2846C31.8262 41.1437 31.0084 40.8571 30.2383 40.4125C26.7589 38.4036 25.5665 33.9545 27.5752 30.475Z");
  const CENTER = [33.9, 34.1];
  const lit = (r, c) => r < 5 && c >= 9 && c < 18;

  function week(canvas, { animate, shift = 15 }) {
    const ctx = canvas.getContext("2d");
    let cell = 0, offset = 0, w = 0, phase = 0, running = animate && !reduce, inView = false, last = 0, raf = 0;
    function size() {
      w = canvas.clientWidth;
      if (!w) return;
      // On a phone the field crops to the working day instead of shrinking past legibility.
      cell = Math.max(w / 24, 30);
      offset = cell === w / 24 ? 0 : w / 2 - 13.5 * cell;
      const h = cell * 7, d = Math.min(devicePixelRatio || 1, 2);
      canvas.style.height = h + "px";
      canvas.width = Math.round(w * d);
      canvas.height = Math.round(h * d);
      ctx.setTransform(d, 0, 0, d, 0, 0);
      clear();
      // Drawn: the hero fades the field in and brings its notes after it (CSS); until now the canvas was blank.
      canvas.dataset.drawn = "";
    }
    // The notes on the field (.ftag): the cells under each label are left empty, so a label sits in a clean lane
    // instead of on top of half-hidden commas. Measured again when a label changes width (the language).
    const notes = $$(".ftag", canvas.parentElement);
    const empty = new Set();
    function clear() {
      empty.clear();
      for (const t of notes) {
        const label = t.firstElementChild;
        if (offset || !cell || !label?.offsetWidth) continue; // hidden, or the field is cropped (a phone)
        const r = Math.round(t.offsetTop / cell), x = t.offsetLeft + label.offsetLeft;
        for (let c = Math.floor(x / cell); c <= Math.floor((x + label.offsetWidth - 1) / cell) && c < 24; c++) empty.add(r * 24 + c);
      }
      draw();
    }
    if (notes.length) { const ro = new ResizeObserver(() => cell && clear()); for (const t of notes) ro.observe(t.firstElementChild); }
    function draw() {
      ctx.clearRect(0, 0, w, cell * 7);
      const k = cell / 26;
      for (let r = 0; r < 7; r++) for (let c = 0; c < 24; c++) {
        const x = offset + c * cell + cell / 2;
        if (x < -cell || x > w + cell || empty.has(r * 24 + c)) continue;
        ctx.save();
        ctx.translate(x, r * cell + cell / 2);
        ctx.rotate(((c * 15 + r * shift + phase) * Math.PI) / 180);
        ctx.scale(k, k);
        ctx.translate(-CENTER[0], -CENTER[1]);
        ctx.fillStyle = lit(r, c) ? "#FFFFFF" : "#F68B64";
        ctx.fill(COMMA);
        ctx.restore();
      }
    }
    // At most 30 frames a second: at 15° a second, that is half a degree a frame, which reads as smooth.
    let drawn = 0;
    function tick(t) {
      raf = 0;
      if (!running || !inView || document.hidden || !ready) { last = 0; return; }
      if (last) phase = (phase + (t - last) * 0.015) % 360; // 1 s = 1 hour = 15°
      last = t;
      if (t - drawn >= 32) { drawn = t; draw(); }
      raf = requestAnimationFrame(tick);
    }
    const start = () => { if (running && inView && ready && !document.hidden && !raf) raf = requestAnimationFrame(tick); };
    // The field is drawn still at once; it starts turning only once the page has loaded and the browser is idle, so
    // the animation never competes with the first paint or the first tap.
    let ready = false;
    const go = () => { ready = true; start(); };
    const idle = () => ("requestIdleCallback" in window ? requestIdleCallback(go, { timeout: 2500 }) : setTimeout(go, 1200));
    if (animate) document.readyState === "complete" ? idle() : addEventListener("load", idle, { once: true });
    new IntersectionObserver(([e]) => { inView = e.isIntersecting; start(); }).observe(canvas);
    document.addEventListener("visibilitychange", start);
    new ResizeObserver(size).observe(canvas);
    return {
      get running() { return running; },
      toggle() { running = !running; start(); return running; },
    };
  }

  const hero = week($("#field"), { animate: true });
  week($("#field-end"), { animate: false, shift: 45 });
  const pause = $("#pause");
  const syncPause = () => {
    pause.innerHTML = hero.running
      ? '<svg viewBox="0 0 10 10" aria-hidden="true"><rect x="1.5" y="1" width="2.4" height="8" rx=".6"/><rect x="6.1" y="1" width="2.4" height="8" rx=".6"/></svg><span class="zh">暂停</span><span class="en">Pause</span>'
      : '<svg class="play" viewBox="0 0 10 10" aria-hidden="true"><path d="M2 1.6v6.8a.6.6 0 0 0 .9.5l5.6-3.4a.6.6 0 0 0 0-1L2.9 1.1a.6.6 0 0 0-.9.5Z"/></svg><span class="zh">继续</span><span class="en">Play</span>';
  };
  // Still under reduced motion: the clock and its pause have nothing to say.
  if (reduce) pause.parentElement.hidden = true;
  pause.addEventListener("click", () => { hero.toggle(); syncPause(); });
  syncPause();
})();
