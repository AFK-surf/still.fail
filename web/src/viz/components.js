// still.fail's components for inline visualizations: a few atoms (a card, a number, a status, a button, a progress
// bar) and charts drawn from the data an agent gives them, in still.fail's look (ember-viz.css styles them and gives
// the design tokens); the rest is written with the tokens. Runs in every
// fragment's frame after the bridge (Viz.tsx, the app's viz_file.mbt). How agents use them:
// station/src/skills/stillfail-viz.md. Plain custom elements without a shadow root: the stylesheet and the theme's
// tokens reach what they draw, and charts drawn with var(--sf-…) follow the theme without being drawn again.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const TONE_INK = {
    ok: "--sf-green", green: "--sf-green", busy: "--sf-amber", warn: "--sf-amber", amber: "--sf-amber",
    error: "--sf-red", red: "--sf-red", info: "--sf-blue", blue: "--sf-blue", purple: "--sf-purple", off: "--sf-muted",
    ink: "--sf-ink", muted: "--sf-muted",
  };

  /** An element: tag (with .classes), attributes (on* are listeners), children (strings are text). */
  const h = (tag, attrs = {}, ...kids) => {
    const [name, ...classes] = tag.split(".");
    const el = document.createElement(name);
    if (classes.length) el.className = classes.join(" ");
    for (const [k, v] of Object.entries(attrs)) {
      if (v === undefined || v === null || v === false) continue;
      if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (k === "style") el.style.cssText = v;
      else el.setAttribute(k, v === true ? "" : String(v));
    }
    for (const kid of kids.flat(Infinity)) if (kid !== undefined && kid !== null && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
    return el;
  };
  const s = (tag, attrs = {}, ...kids) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) el.setAttribute(k, String(v));
    for (const kid of kids.flat(Infinity)) if (kid) el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    return el;
  };
  /** Puts what is given in place of an element's children, leaving out what is not there. */
  const put = (el, ...kids) => el.replaceChildren(...kids.flat(Infinity).filter((k) => k !== undefined && k !== null && k !== false && k !== ""));
  const ink = (tone, i = 0) => `var(${TONE_INK[tone] ?? `--sf-series-${(i % 6) + 1}`})`;

  /** The element's data: its `data` attribute, else a <script type="application/json"> inside it. */
  const dataOf = (el) => {
    const raw = el.getAttribute("data") ?? el.querySelector(":scope > script[type='application/json']")?.textContent;
    if (!raw) return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      put(el, h("sf-note", {}, `${el.localName}: its data is not JSON (${e.message})`));
      return undefined;
    }
  };
  const num = (v) => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v.replace(/[,_]/g, ""))) ? Number(v.replace(/[,_]/g, "")) : NaN);
  const fmt = (n, digits = 2) => (Number.isFinite(n) ? n.toLocaleString(undefined, { maximumFractionDigits: digits }) : String(n));

  /** Draws once its children are there (an element is upgraded as its tag is read, before what is inside it). */
  class Base extends HTMLElement {
    connectedCallback() {
      if (this._drawn) return;
      const go = () => {
        if (this._drawn || !this.isConnected) return;
        this._drawn = true;
        try {
          this.draw();
        } catch (e) {
          put(this, h("sf-note", {}, `${this.localName}: ${e.message}`));
          postMessage({ emberViz: true, type: "error", message: `${this.localName}: ${e.message}` }, "*");
        }
      };
      if (document.readyState === "loading") addEventListener("DOMContentLoaded", go, { once: true });
      else queueMicrotask(go);
    }
    draw() {}
  }
  const define = (name, cls) => { if (!customElements.get(name)) customElements.define(name, cls); };

  // ── Card: a ground with a title ─────────────────────────────────────────────────────
  define("sf-card", class extends Base {
    draw() {
      const title = this.getAttribute("title");
      const note = this.getAttribute("note");
      if (title || note) {
        this.removeAttribute("title"); // not a tooltip
        this.prepend(h("div.sf-head", {}, title && h("div.sf-title", {}, title), note && h("div.sf-sub", {}, note)));
      }
    }
  });

  /** A small line of values (a trend), as wide as it is given, in ink. */
  const spark = (values, { w = 80, hgt = 22, tone } = {}) => {
    const vs = values.map(num).filter(Number.isFinite);
    const svg = s("svg", { class: "sf-spark", viewBox: `0 0 ${w} ${hgt}`, preserveAspectRatio: "none", width: w, height: hgt });
    if (vs.length < 2) return svg;
    const lo = Math.min(...vs), hi = Math.max(...vs) === lo ? lo + 1 : Math.max(...vs);
    const pts = vs.map((v, i) => `${(i / (vs.length - 1)) * w},${2 + (1 - (v - lo) / (hi - lo)) * (hgt - 4)}`);
    svg.append(s("polyline", { points: pts.join(" "), fill: "none", stroke: tone ? ink(tone) : "var(--sf-ink)", "stroke-width": 1.5, "stroke-linejoin": "round", "stroke-linecap": "round", "vector-effect": "non-scaling-stroke" }));
    return svg;
  };
  const listOf = (raw) => { try { return JSON.parse(raw); } catch { return String(raw).split(/[\s,]+/).filter(Boolean); } };

  // ── A number with its label ─────────────────────────────────────────────────────────
  define("sf-stat", class extends Base {
    draw() {
      const value = this.getAttribute("value") ?? this.textContent.trim();
      const tone = this.getAttribute("tone");
      const note = this.getAttribute("note");
      const delta = this.getAttribute("delta");
      const trend = this.getAttribute("trend");
      put(this,
        h("span.sf-stat-label", {}, this.getAttribute("label") ?? ""),
        h("span.sf-stat-value", {}, /^[\s+\-]*[\d.,]+$/.test(value) && Number.isFinite(num(value)) ? fmt(num(value)) : value, this.hasAttribute("unit") && h("span.sf-stat-unit", {}, this.getAttribute("unit"))),
        (note || delta) && h("span.sf-stat-note", {},
          tone && h("i.sf-dot", { "data-tone": tone }),
          delta && h("span.sf-delta", { "data-tone": this.getAttribute("delta-tone") ?? undefined }, /^[+]/.test(delta) ? `↑ ${delta.slice(1)}` : /^[-−]/.test(delta) ? `↓ ${delta.slice(1)}` : delta),
          note && h("span", { style: tone && tone !== "off" ? `color:${ink(tone)}` : undefined }, note)),
        trend && h("span.sf-stat-trend", {}, spark(listOf(trend), { w: 120, hgt: 28, tone: tone && tone !== "off" ? tone : undefined })),
      );
    }
  });

  // ── Status: a dot and words ─────────────────────────────────────────────────────────
  define("sf-status", class extends Base {
    draw() {
      this.prepend(h("i.sf-dot", { "data-tone": this.getAttribute("tone") ?? this.getAttribute("state") ?? "" }));
    }
  });
  define("sf-spark", class extends Base {
    draw() {
      put(this, spark(listOf(this.getAttribute("data") ?? this.textContent), { w: num(this.getAttribute("width")) || 80, hgt: num(this.getAttribute("height")) || 20, tone: this.getAttribute("tone") ?? undefined }));
    }
  });


  // ── Progress ────────────────────────────────────────────────────────────────────────
  define("sf-progress", class extends Base {
    draw() {
      const value = num(this.getAttribute("value")) || 0;
      const max = num(this.getAttribute("max")) || 100;
      const share = Math.max(0, Math.min(1, value / max));
      const label = this.getAttribute("label");
      const said = this.getAttribute("note") ?? (max === 100 ? `${fmt(value, 1)}%` : `${fmt(value)} / ${fmt(max)}`);
      put(this, 
        (label || said) && h("div.sf-progress-head", {}, h("span", {}, label ?? ""), h("span", {}, said)),
        h("div.sf-progress-track", { role: "progressbar", "aria-valuenow": value, "aria-valuemax": max }, h("div.sf-progress-fill", { style: `width:${share * 100}%` })),
      );
    }
  });


  // ── Things to send: what is clicked goes into the chat's composer for the person to send ───────────────────
  const send = (prompt) => window.ember?.sendFollowUpMessage({ prompt }).catch(() => {});

  define("sf-button", class extends Base {
    draw() {
      const words = this.getAttribute("send");
      const b = h("button.sf-button", {
        type: "button", "data-primary": this.hasAttribute("primary") || undefined, "data-quiet": this.hasAttribute("quiet") || undefined,
        "data-small": this.hasAttribute("small") || undefined, onclick: words ? () => send(words) : undefined,
      }, ...this.childNodes);
      put(this, b);
    }
  });

  // ── Charts ──────────────────────────────────────────────────────────────────────────
  /** Round steps for an axis from 0 (or the least, when below it) to the most. */
  const ticks = (lo, hi, n = 4) => {
    if (hi === lo) hi = lo + 1;
    const raw = (hi - lo) / n;
    const mag = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((x) => x >= raw) ?? raw;
    const start = Math.floor(lo / step) * step;
    const out = [];
    for (let v = start; v <= hi + step * 1e-9; v += step) out.push(Number(v.toPrecision(12)));
    if (out[out.length - 1] < hi) out.push(Number((out[out.length - 1] + step).toPrecision(12)));
    return out;
  };
  const short = (n) => {
    const a = Math.abs(n);
    return a >= 1e9 ? `${fmt(n / 1e9, 1)}B` : a >= 1e6 ? `${fmt(n / 1e6, 1)}M` : a >= 1e4 ? `${fmt(n / 1e3, 1)}k` : fmt(n);
  };

  define("sf-chart", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      this._data = d;
      this._width = 0;
      this.render();
      new ResizeObserver(() => { if (Math.round(this.clientWidth) !== this._width) this.render(); }).observe(this);
    }
    render() {
      const d = this._data;
      const type = this.getAttribute("type") ?? "bar";
      const unit = this.getAttribute("unit") ?? "";
      const width = Math.round(this.clientWidth) || 600;
      this._width = width;
      if (type === "donut" || type === "pie") return this.donut(d, unit);
      if (type === "scatter") return this.scatter(d, unit, width);
      if (type === "hbar") return this.hbar(d, unit);
      const labels = d.labels ?? [];
      const series = (d.series ?? [{ name: d.name ?? "", values: d.values ?? [], tone: d.tone }]).map((sr, i) => ({ ...sr, color: sr.tone ? ink(sr.tone) : ink(null, i) }));
      const stacked = this.hasAttribute("stacked") && type === "bar";
      const height = num(this.getAttribute("height")) || 200;
      const all = stacked ? labels.map((_, i) => series.reduce((a, sr) => a + (num(sr.values[i]) || 0), 0)) : series.flatMap((sr) => sr.values.map(num).filter(Number.isFinite));
      const lo = Math.min(0, ...all);
      const hi = Math.max(0, ...all);
      const ys = ticks(lo, hi);
      const y0 = ys[0], y1 = ys[ys.length - 1];
      const labelW = Math.max(...ys.map((v) => (short(v) + unit).length)) * 6.5 + 8;
      const left = labelW, right = 4, top = 8, bottom = 22;
      const plotW = Math.max(40, width - left - right), plotH = height - top - bottom;
      const Y = (v) => top + plotH - ((v - y0) / (y1 - y0)) * plotH;
      const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, height, role: "img" });
      for (const v of ys) {
        svg.append(s("line", { class: "sf-chart-grid", x1: left, x2: width - right, y1: Y(v), y2: Y(v) }));
        svg.append(s("text", { class: "sf-chart-axis", x: left - 8, y: Y(v), "text-anchor": "end", "dominant-baseline": "middle" }, short(v) + unit));
      }
      const n = Math.max(1, labels.length);
      const band = plotW / n;
      const every = Math.max(1, Math.ceil((labels.reduce((m, l) => Math.max(m, String(l).length), 0) * 6.5 + 12) / band));
      labels.forEach((l, i) => {
        if (i % every) return;
        const x = type === "bar" ? left + band * (i + .5) : left + (n === 1 ? plotW / 2 : (plotW * i) / (n - 1));
        svg.append(s("text", { class: "sf-chart-axis", x, y: height - 6, "text-anchor": n > 1 && type !== "bar" && i === 0 ? "start" : n > 1 && type !== "bar" && i === n - 1 ? "end" : "middle" }, l));
      });
      const tip = (i, sr, v) => `${labels[i] ?? ""}${sr.name ? ` · ${sr.name}` : ""}: ${fmt(v)}${unit}`;
      if (type === "bar") {
        const inner = band * .72;
        const each = stacked ? inner : inner / series.length;
        const r = Math.min(4, each / 4);
        labels.forEach((_, i) => {
          let acc = 0;
          series.forEach((sr, k) => {
            const v = num(sr.values[i]) || 0;
            const x = left + band * i + (band - inner) / 2 + (stacked ? 0 : each * k);
            const from = stacked ? acc : 0;
            acc += v;
            const ya = Y(Math.max(from, from + v)), yb = Y(Math.min(from, from + v));
            const w = Math.max(1, each - (stacked || series.length === 1 ? 0 : 2));
            const hgt = Math.max(v === 0 ? 0 : 1, yb - ya);
            const top_ = !stacked || k === series.length - 1;
            const path = top_ && hgt > r
              ? `M${x},${ya + hgt}V${ya + r}Q${x},${ya} ${x + r},${ya}H${x + w - r}Q${x + w},${ya} ${x + w},${ya + r}V${ya + hgt}Z`
              : `M${x},${ya}h${w}v${hgt}h${-w}Z`;
            svg.append(s("path", { d: path, fill: sr.color, class: "sf-hit", "data-tooltip": tip(i, sr, v) }));
          });
        });
      } else {
        const X = (i) => left + (n === 1 ? plotW / 2 : (plotW * i) / (n - 1));
        series.forEach((sr) => {
          const pts = sr.values.map((v, i) => [X(i), Y(num(v))]).filter(([, y]) => Number.isFinite(y));
          if (!pts.length) return;
          const line = pts.map(([x, y], i) => `${i ? "L" : "M"}${x},${y}`).join("");
          if (type === "area") svg.append(s("path", { d: `${line}L${pts[pts.length - 1][0]},${Y(Math.max(0, y0))}L${pts[0][0]},${Y(Math.max(0, y0))}Z`, fill: sr.color, "fill-opacity": series.length > 1 ? .12 : .16 }));
          svg.append(s("path", { d: line, fill: "none", stroke: sr.color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
          sr.values.forEach((v, i) => {
            if (!Number.isFinite(num(v))) return;
            svg.append(s("circle", { cx: X(i), cy: Y(num(v)), r: pts.length > 24 ? 0 : 3, fill: sr.color }));
            svg.append(s("rect", { x: X(i) - Math.max(6, plotW / n / 2), y: top, width: Math.max(12, plotW / n), height: plotH, fill: "transparent", "data-tooltip": tip(i, sr, num(v)) }));
          });
        });
      }
      const legend = series.length > 1 && h("div.sf-chart-legend", {}, series.map((sr) => h("span", {}, h("i", { style: `background:${sr.color}` }), sr.name)));
      put(this, this.title_(), svg, legend);
    }
    title_() {
      const t = this.getAttribute("title");
      if (t) this.setAttribute("data-title", t), this.removeAttribute("title");
      const said = this.getAttribute("data-title");
      return said && h("div.sf-title", {}, said);
    }
    hbar(d, unit) {
      const items = d.items ?? (d.labels ?? []).map((l, i) => ({ label: l, value: (d.values ?? [])[i] }));
      const max = num(this.getAttribute("max")) || Math.max(0, ...items.map((it) => num(it.value) || 0)) || 1;
      put(this, this.title_(), h("div.sf-hbars", {}, items.map((it, i) => [
        h("span.sf-bar-label", {}, it.label),
        h("span.sf-bar-track", {}, h("span.sf-bar-fill", { style: `width:${Math.max(0, Math.min(100, ((num(it.value) || 0) / max) * 100))}%;background:${it.tone ? ink(it.tone) : "var(--sf-ink)"}`, "data-tooltip": `${it.label}: ${fmt(num(it.value))}${unit}` })),
        h("span.sf-bar-value", {}, it.note ?? `${fmt(num(it.value))}${unit}`),
      ])));
    }
    scatter(d, unit, width) {
      const series = (d.series ?? [{ name: d.name ?? "", points: d.points ?? [] }]).map((sr, i) => ({ ...sr, color: sr.tone ? ink(sr.tone) : ink(null, i) }));
      const pts = series.flatMap((sr) => sr.points.map((p) => [num(p[0] ?? p.x), num(p[1] ?? p.y)]));
      const height = num(this.getAttribute("height")) || 220;
      const xs = ticks(Math.min(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[0])));
      const ys = ticks(Math.min(0, ...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[1])));
      const xunit = this.getAttribute("x-unit") ?? "";
      const left = Math.max(...ys.map((v) => (short(v) + unit).length)) * 6.5 + 8, right = 8, top = 8, bottom = 22;
      const pw = width - left - right, ph = height - top - bottom;
      const X = (v) => left + ((v - xs[0]) / (xs[xs.length - 1] - xs[0])) * pw;
      const Y = (v) => top + ph - ((v - ys[0]) / (ys[ys.length - 1] - ys[0])) * ph;
      const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, height, role: "img" });
      for (const v of ys) svg.append(s("line", { class: "sf-chart-grid", x1: left, x2: width - right, y1: Y(v), y2: Y(v) }), s("text", { class: "sf-chart-axis", x: left - 8, y: Y(v), "text-anchor": "end", "dominant-baseline": "middle" }, short(v) + unit));
      for (const v of xs) svg.append(s("text", { class: "sf-chart-axis", x: X(v), y: height - 6, "text-anchor": "middle" }, short(v) + xunit));
      series.forEach((sr) => sr.points.forEach((p) => {
        const x = num(p[0] ?? p.x), y = num(p[1] ?? p.y);
        if (!Number.isFinite(x) || !Number.isFinite(y)) return;
        svg.append(s("circle", { cx: X(x), cy: Y(y), r: 4, fill: sr.color, "fill-opacity": .85, class: "sf-hit", "data-tooltip": `${p.label ?? p[2] ?? (sr.name || "")}${p.label || p[2] || sr.name ? ": " : ""}${fmt(x)}${xunit}, ${fmt(y)}${unit}` }));
      }));
      const legend = series.length > 1 && h("div.sf-chart-legend", {}, series.map((sr) => h("span", {}, h("i", { style: `background:${sr.color};border-radius:50%` }), sr.name)));
      put(this, this.title_(), svg, legend);
    }
    donut(d, unit) {
      const items = d.items ?? (d.labels ?? []).map((l, i) => ({ label: l, value: (d.values ?? [])[i] }));
      const total = items.reduce((a, it) => a + (num(it.value) || 0), 0) || 1;
      const R = 60, r = this.getAttribute("type") === "pie" ? 0 : 42, c = 70;
      const svg = s("svg", { viewBox: "0 0 140 140", role: "img" });
      let a = -Math.PI / 2;
      items.forEach((it, i) => {
        const v = num(it.value) || 0;
        const span = (v / total) * Math.PI * 2;
        const color = it.tone ? ink(it.tone) : ink(null, i);
        const b = a + span;
        const big = span > Math.PI ? 1 : 0;
        const p = (rad, ang) => `${c + rad * Math.cos(ang)},${c + rad * Math.sin(ang)}`;
        const gap = items.length > 1 ? .012 : 0;
        const d_ = span >= Math.PI * 2 - 1e-6
          ? `M${c - R},${c}a${R},${R} 0 1,0 ${R * 2},0a${R},${R} 0 1,0 ${-R * 2},0${r ? `M${c - r},${c}a${r},${r} 0 1,1 ${r * 2},0a${r},${r} 0 1,1 ${-r * 2},0` : ""}Z`
          : `M${p(R, a + gap)}A${R},${R} 0 ${big},1 ${p(R, b - gap)}${r ? `L${p(r, b - gap)}A${r},${r} 0 ${big},0 ${p(r, a + gap)}` : `L${c},${c}`}Z`;
        svg.append(s("path", { d: d_, fill: color, "fill-rule": "evenodd", class: "sf-hit", "data-tooltip": `${it.label}: ${fmt(v)}${unit} (${fmt((v / total) * 100, 1)}%)` }));
        it.color = color;
        a = b;
      });
      const center = this.getAttribute("center");
      if (r && center !== "") svg.append(s("text", { class: "sf-chart-center", x: c, y: c, "text-anchor": "middle", "dominant-baseline": "central" }, center ?? `${short(total)}${unit}`));
      const legend = h("div.sf-chart-legend", {}, items.map((it) => h("span", {}, h("span", { style: "display:inline-flex;align-items:center;gap:6px" }, h("i", { style: `background:${it.color}` }), it.label), h("b", {}, `${fmt(num(it.value))}${unit}`))));
      put(this, this.title_(), h("div.sf-chart-donut", {}, svg, legend));
    }
  });
})();
