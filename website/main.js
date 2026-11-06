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

  // ---- Language: both are in the page, one is shown ----
  function setLang(l, remember) {
    root.dataset.lang = l;
    root.lang = l === "en" ? "en" : "zh-CN";
    for (const b of $$("[data-set-lang]")) b.setAttribute("aria-pressed", String(b.dataset.setLang === l));
    for (const a of $$("[data-legal]")) a.href = (l === "en" ? "/en" : "") + new URL(a.href).pathname.replace(/^\/en/, "");
    if (remember) store.set("monoid.site.lang", l);
  }
  setLang(root.dataset.lang === "en" ? "en" : "zh", false);
  for (const b of $$("[data-set-lang]")) b.addEventListener("click", () => setLang(b.dataset.setLang, true));

  // ---- Mobile menu ----
  const nav = $("#nav");
  const menu = $(".menu-btn");
  menu.addEventListener("click", () => {
    const open = !nav.hasAttribute("data-open");
    nav.toggleAttribute("data-open", open);
    menu.setAttribute("aria-expanded", String(open));
  });
  for (const a of $$(".nav-list a")) a.addEventListener("click", () => { nav.removeAttribute("data-open"); menu.setAttribute("aria-expanded", "false"); });

  // ---- Which section is on screen: its nav link is marked ----
  const links = new Map($$(".nav-list a").map((a) => [a.hash.slice(1), a]));
  const spy = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      for (const a of links.values()) a.removeAttribute("aria-current");
      links.get(e.target.id)?.setAttribute("aria-current", "true");
    }
  }, { rootMargin: "-45% 0px -50% 0px" });
  for (const id of links.keys()) { const s = document.getElementById(id); if (s) spy.observe(s); }

  // ---- Tabs (the product overview and the devices) ----
  for (const group of $$("[data-tabs]")) {
    // Real tabs (role=tab) keep one tab stop and arrow keys; the overview's accordion buttons (data-tab) are each a stop.
    const tabs = $$('[role="tab"], [data-tab]', group);
    const select = (tab, focus) => {
      for (const t of tabs) {
        const on = t === tab;
        if (t.hasAttribute("data-tab")) t.setAttribute("aria-expanded", String(on));
        else { t.setAttribute("aria-selected", String(on)); t.tabIndex = on ? 0 : -1; }
        t.closest(".ov-item")?.toggleAttribute("data-on", on);
        const panel = document.getElementById(t.getAttribute("aria-controls"));
        if (panel) panel.hidden = !on;
      }
      if (focus) tab.focus();
    };
    // While the devices play on scroll (initScrolly), picking a tab scrolls to it instead.
    const pick = (i, focus) => (group.onPick ? group.onPick(i, focus) : select(tabs[i], focus));
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

  // ---- Every device, played by scrolling (large screens with motion allowed: html.scrolly, set in the head) ----
  // The tabs stay on screen with CSS (position: sticky in a tall track, sized from the first paint, so nothing moves when
  // the script arrives); GSAP's ScrollTrigger only scrubs a timeline through it: the iPhone Duo unfolds, then Android,
  // desktop, the web and Slack take its place. GSAP is fetched only as the section comes near.
  const loadScript = (src) => new Promise((ok, fail) => {
    const s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = fail;
    document.head.appendChild(s);
  });
  function initScrolly() {
    const { gsap, ScrollTrigger } = window;
    gsap.registerPlugin(ScrollTrigger);
    const sec = $("#devices"), track = $(".dv-track", sec), sticky = $(".dv-sticky", sec), group = sticky;
    const tabs = $$('[role="tab"]', sticky), panels = $$(".fpanel", sticky);
    const P = (n, s) => $(s, panels[n]), PP = (n, s) => $$(s, panels[n]);
    const txt = (n) => [...$(".txt", panels[n]).children];
    const duo = P(0, ".duo"), [left] = duo.children;
    const navH = () => $("#nav").offsetHeight;
    const setH = () => track.style.setProperty("--dv-h", sticky.offsetHeight + "px");
    setH();
    for (const p of panels) p.hidden = false;
    gsap.set(panels.slice(1), { autoAlpha: 0 });
    // Folded: only the cover screen shows; the inner one is turned away behind the hinge.
    gsap.set(duo, { clipPath: "inset(0% 0% 0% 50% round 30px)", xPercent: -25 });
    gsap.set(left, { rotationY: 80, transformOrigin: "100% 50%", transformPerspective: 900, autoAlpha: 0.15 });
    gsap.set(P(0, ".pose-open"), { autoAlpha: 0 });

    const tl = gsap.timeline({ defaults: { ease: "power2.inOut", duration: 1 } });
    tl.addLabel("closed")
      .to({}, { duration: 0.35 })
      .to(duo, { clipPath: "inset(0% 0% 0% 0% round 30px)", xPercent: 0 }, ">")
      .to(left, { rotationY: 0, autoAlpha: 1 }, "<")
      .to(P(0, ".pose-closed"), { autoAlpha: 0, duration: 0.3 }, "<")
      .to(P(0, ".pose-open"), { autoAlpha: 1, duration: 0.3 }, "<0.7")
      .addLabel("open", ">");
    /** From panel `a` to panel `b`: its words leave upward and the next ones come up; `out(at)` and `inn(at)` add the
     *  pictures' moves to the timeline at `at` seconds (numbers: GSAP reads no "label+=a+=b"). */
    const step = (a, b, label, out, inn) => {
      const L = `to-${label}`;
      tl.to({}, { duration: 0.45 })
        .addLabel(L)
        .to(txt(a), { y: -22, autoAlpha: 0, stagger: 0.04, duration: 0.45 }, L)
        .to(panels[a], { autoAlpha: 0, duration: 0.35 }, `${L}+=0.45`)
        .to(panels[b], { autoAlpha: 1, duration: 0.35 }, `${L}+=0.3`)
        .from(txt(b), { y: 22, autoAlpha: 0, stagger: 0.05, duration: 0.55 }, `${L}+=0.5`);
      out(tl.labels[L]);
      inn(tl.labels[L] + 0.4);
      tl.addLabel(label); // at the end, once everything of this step has arrived
    };
    // A from-tween shows its start at once (GSAP's default), so a panel never flashes its last frame as it fades in.
    const from = (el, vars, at) => tl.from(el, vars, at);
    step(0, 1, "android",
      (at) => tl.to(duo, { x: -90, rotationY: 22, transformPerspective: 1200, autoAlpha: 0, duration: 0.7 }, at),
      (at) => {
        from(P(1, ".phone"), { y: 170, rotation: -8, autoAlpha: 0, duration: 0.8, ease: "power3.out" }, at);
        from(P(1, ".notif"), { y: -36, autoAlpha: 0, duration: 0.4, ease: "back.out(1.6)" }, at + 0.65);
      });
    step(1, 2, "desktop",
      (at) => tl.to(P(1, ".phone"), { x: 140, scale: 0.7, autoAlpha: 0, duration: 0.7 }, at),
      (at) => {
        from(P(2, ".laptop"), { scale: 0.86, y: 40, autoAlpha: 0, duration: 0.7, ease: "power3.out" }, at);
        from(PP(2, ".meter i"), { scaleX: 0, transformOrigin: "0% 50%", stagger: 0.08, duration: 0.5 }, at + 0.4);
      });
    step(2, 3, "web",
      (at) => tl.to(P(2, ".laptop"), { y: -30, autoAlpha: 0, duration: 0.6 }, at),
      (at) => {
        from(P(3, ".laptop"), { y: 40, autoAlpha: 0, duration: 0.6, ease: "power3.out" }, at);
        from(P(3, ".win-bar > span"), { scaleX: 0, transformOrigin: "0% 50%", duration: 0.4 }, at + 0.35);
        from(PP(3, ".main > *"), { y: 14, autoAlpha: 0, stagger: 0.14, duration: 0.4 }, at + 0.5);
      });
    step(3, 4, "slack",
      (at) => tl.to(P(3, ".laptop"), { scale: 0.94, autoAlpha: 0, duration: 0.6 }, at),
      (at) => {
        from(P(4, ".slack"), { y: 50, autoAlpha: 0, duration: 0.6, ease: "power3.out" }, at);
        from(PP(4, ".slack .msg"), { x: -16, autoAlpha: 0, stagger: 0.16, duration: 0.4 }, at + 0.4);
      });
    tl.to({}, { duration: 0.45 });

    const stops = ["closed", "open", "android", "desktop", "web", "slack"];
    const tabOf = { closed: 0, open: 0, android: 1, desktop: 2, web: 3, slack: 4 };
    const at = (label) => tl.labels[label] / tl.duration();
    const count = $(".dv-count b", sticky), bar = $(".dv-progress i", sticky);
    let current = -1;
    const show = (i) => {
      if (i === current) return;
      current = i;
      tabs.forEach((t, k) => { t.setAttribute("aria-selected", String(k === i)); t.tabIndex = k === i ? 0 : -1; });
      panels.forEach((p, k) => { p.inert = k !== i; p.setAttribute("aria-hidden", String(k !== i)); });
      count.textContent = String(i + 1).padStart(2, "0");
    };
    const st = ScrollTrigger.create({
      trigger: track,
      start: () => `top top+=${navH() + 20}`,
      end: () => `bottom top+=${navH() + 20 + sticky.offsetHeight}`,
      animation: tl,
      scrub: 0.6,
      // Snap to the nearest stop, not to where the flick would carry: a fast scroll never skips a device unseen.
      snap: { snapTo: stops.map(at), inertia: false, duration: { min: 0.2, max: 0.6 }, delay: 0.12, ease: "power1.inOut" },
      invalidateOnRefresh: true,
      onUpdate(self) {
        bar.style.transform = `scaleX(${self.progress})`;
        const t = self.progress * tl.duration() + 0.05; // where the scroll is, not where the scrub has got to
        let label = "closed";
        for (const s of stops) if (tl.labels[s] <= t) label = s;
        // A panel counts as shown once its words have arrived (half-way into its step).
        for (const s of stops.slice(2)) if (tl.labels[`to-${s}`] + 0.5 <= t) label = s;
        show(tabOf[label]);
      },
    });
    ScrollTrigger.addEventListener("refreshInit", setH);
    show(0);
    group.onPick = (i, focus) => {
      const label = ["open", "android", "desktop", "web", "slack"][i];
      scrollTo({ top: st.start + (st.end - st.start) * at(label), behavior: "smooth" });
      if (focus) tabs[i].focus({ preventScroll: true });
    };
  }
  if (root.classList.contains("scrolly")) {
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
  if (reduce || !("IntersectionObserver" in window)) {
    for (const el of $$(".rv")) el.classList.add("in");
  } else {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }, { rootMargin: "0px 0px -8% 0px" });
    for (const el of $$(".rv")) io.observe(el);
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
      draw();
    }
    function draw() {
      ctx.clearRect(0, 0, w, cell * 7);
      const k = cell / 26;
      for (let r = 0; r < 7; r++) for (let c = 0; c < 24; c++) {
        const x = offset + c * cell + cell / 2;
        if (x < -cell || x > w + cell) continue;
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
      ? '<span class="zh">暂停</span><span class="en">Pause</span>'
      : '<span class="zh">继续</span><span class="en">Play</span>';
  };
  if (reduce) pause.hidden = true;
  pause.addEventListener("click", () => { hero.toggle(); syncPause(); });
  syncPause();
})();
