// still.fail's components for inline visualizations: <sf-…> elements an agent writes with its data, drawn in
// still.fail's look (ember-viz.css styles them) so a figure seldom needs styles or scripts of its own. Runs in every
// fragment's frame after the bridge (Viz.tsx, the app's viz_file.mbt). How agents use them:
// station/src/skills/stillfail-viz.md. Plain custom elements without a shadow root: the stylesheet and the theme's
// tokens reach what they draw, and charts drawn with var(--sf-…) follow the theme without being drawn again.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const TONES = ["ok", "busy", "warn", "error", "off", "info", "blue", "green", "amber", "red", "purple"];
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
    for (const kid of kids.flat()) if (kid !== undefined && kid !== null && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
    return el;
  };
  const s = (tag, attrs = {}, ...kids) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) el.setAttribute(k, String(v));
    for (const kid of kids.flat()) if (kid) el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    return el;
  };
  /** Puts what is given in place of an element's children, leaving out what is not there. */
  const put = (el, ...kids) => el.replaceChildren(...kids.flat().filter((k) => k !== undefined && k !== null && k !== false && k !== ""));
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
  /** Whether a cell reads as a number (a count, a time, a share, an amount): such a column is set right. */
  const numeric = (v) => typeof v === "number" || (typeof v === "string" && /^[\s+\-−]*[$¥€£]?[\d.,:]+\s*(%|ms|s|m|h|d|k|K|M|G|GB|MB|KB|TB|x|×|分|秒|天|小时|个|次|元)?$/.test(v));

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

  // ── A number with its label ─────────────────────────────────────────────────────────
  define("sf-stat", class extends Base {
    draw() {
      const value = this.getAttribute("value") ?? this.textContent.trim();
      const tone = this.getAttribute("tone");
      const note = this.getAttribute("note");
      put(this, 
        h("span.sf-stat-label", {}, this.getAttribute("label") ?? ""),
        h("span.sf-stat-value", {}, /^[\s+\-]*[\d.,]+$/.test(value) && Number.isFinite(num(value)) ? fmt(num(value)) : value, this.hasAttribute("unit") && h("span.sf-stat-unit", {}, this.getAttribute("unit"))),
        note && h("span.sf-stat-note", {}, tone && h("i.sf-dot", { "data-tone": tone }), h("span", { style: tone && tone !== "off" ? `color:${ink(tone)}` : undefined }, note)),
      );
    }
  });

  // ── Status: a dot and words ─────────────────────────────────────────────────────────
  define("sf-status", class extends Base {
    draw() {
      this.prepend(h("i.sf-dot", { "data-tone": this.getAttribute("tone") ?? this.getAttribute("state") ?? "" }));
    }
  });

  /** What a table's or a list's cell shows: text, a number, or {text, status|badge|tone}. */
  const cell = (v) => {
    if (v === null || v === undefined) return "";
    if (typeof v === "number") return fmt(v);
    if (typeof v !== "object") return String(v);
    const text = v.text ?? v.value ?? "";
    if (v.status) return h("sf-status", { tone: v.status }, String(text));
    if (v.badge !== undefined) return h("sf-badge", { tone: v.badge === true ? undefined : v.badge }, String(text));
    if (v.tone) return h("span", { style: `color:${ink(v.tone)}` }, String(text));
    if (v.muted) return h("span", { style: "color:var(--sf-muted)" }, String(text));
    return String(text);
  };
  const plain = (v) => (v && typeof v === "object" ? v.text ?? v.value : v);

  // ── Table: from data, or a <table> inside it ────────────────────────────────────────
  define("sf-table", class extends Base {
    draw() {
      const d = dataOf(this);
      if (d === undefined) return;
      if (!d) {
        const table = this.querySelector("table");
        if (table && !table.parentElement.classList.contains("sf-table-scroll")) table.replaceWith(h("div.sf-table-scroll", {}, table.cloneNode(true)));
        return;
      }
      const rows = d.rows ?? (Array.isArray(d) ? d : []);
      let cols = d.columns ?? (rows[0] && !Array.isArray(rows[0]) ? Object.keys(rows[0]) : []);
      cols = cols.map((c, i) => (typeof c === "string" ? { key: Array.isArray(rows[0]) ? i : c, label: c } : { key: c.key ?? i, label: c.label ?? c.key ?? "", align: c.align }));
      const at = (row, c) => (Array.isArray(row) ? row[typeof c.key === "number" ? c.key : cols.indexOf(c)] : row[c.key]);
      for (const c of cols) {
        const values = rows.map((r) => plain(at(r, c))).filter((v) => v !== undefined && v !== null && v !== "");
        c.num = c.align ? c.align === "right" : values.length > 0 && values.every(numeric);
      }
      put(this, h("div.sf-table-scroll", {}, h("table", {},
        h("thead", {}, h("tr", {}, cols.map((c) => h("th", { "data-num": c.num || undefined }, c.label)))),
        h("tbody", {}, rows.map((r) => h("tr", {}, cols.map((c) => h("td", { "data-num": c.num || undefined }, cell(at(r, c))))))),
      )));
    }
  });

  // ── Horizontal bars: label, bar, value ──────────────────────────────────────────────
  define("sf-bars", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      const items = (Array.isArray(d) ? d : d.items ?? []).map((it) => (Array.isArray(it) ? { label: it[0], value: it[1] } : it));
      const max = num(this.getAttribute("max")) || Math.max(0, ...items.map((it) => num(it.value) || 0)) || 1;
      const unit = this.getAttribute("unit") ?? "";
      put(this, ...items.flatMap((it) => [
        h("span.sf-bar-label", { title: it.label }, it.label),
        h("span.sf-bar-track", {}, h("span.sf-bar-fill", { style: `display:block;width:${Math.max(0, Math.min(100, ((num(it.value) || 0) / max) * 100))}%;background:${it.tone ? ink(it.tone) : "var(--sf-ink)"}` })),
        h("span.sf-bar-value", {}, it.note ?? `${fmt(num(it.value))}${unit}`),
      ]));
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

  // ── Facts: key and value ────────────────────────────────────────────────────────────
  define("sf-facts", class extends Base {
    draw() {
      const d = dataOf(this);
      let pairs = d ? (Array.isArray(d) ? d : Object.entries(d)) : null;
      if (!pairs) {
        const dl = this.querySelector("dl");
        if (!dl) return;
        pairs = [...dl.querySelectorAll("dt")].map((dt) => [dt.textContent, dt.nextElementSibling?.localName === "dd" ? [...dt.nextElementSibling.childNodes].map((n) => n.cloneNode(true)) : ""]);
      }
      put(this, ...pairs.flatMap(([k, v]) => [h("span.sf-fact-key", {}, k), h("span.sf-fact-value", {}, Array.isArray(v) ? v : cell(v))]));
    }
  });

  // ── Steps: <sf-step state title note> ───────────────────────────────────────────────
  define("sf-steps", class extends Base {
    draw() {
      const d = dataOf(this);
      const steps = d ? (Array.isArray(d) ? d : d.steps ?? []) : [...this.querySelectorAll(":scope > sf-step")].map((st) => ({
        state: st.getAttribute("state"), title: st.getAttribute("title") ?? "", note: st.getAttribute("note"), body: [...st.childNodes],
      }));
      put(this, ...steps.map((st) => h("div.sf-step", { "data-state": st.state ?? "todo" },
        h("span.sf-step-mark", {}),
        h("div.sf-step-body", {}, h("div.sf-step-title", {}, st.title), st.note && h("div.sf-step-note", {}, st.note), st.body),
      )));
    }
  });
  define("sf-step", class extends HTMLElement {});

  // ── Tabs: <sf-tab label> panels under a segmented choice ────────────────────────────
  define("sf-tabs", class extends Base {
    draw() {
      const tabs = [...this.querySelectorAll(":scope > sf-tab")];
      if (!tabs.length) return;
      const pick = (i) => {
        tabs.forEach((t, k) => { t.hidden = k !== i; });
        [...bar.children].forEach((b, k) => b.setAttribute("aria-selected", String(k === i)));
      };
      const bar = h("div.sf-segmented", { role: "tablist" }, tabs.map((t, i) => h("button.sf-segment", { type: "button", role: "tab", onclick: () => pick(i) }, t.getAttribute("label") ?? `${i + 1}`)));
      this.prepend(bar);
      pick(Math.max(0, tabs.findIndex((t) => t.hasAttribute("selected"))));
    }
  });
  define("sf-tab", class extends HTMLElement {});

  // ── Things to send: what is clicked goes into the chat's composer for the person to send ───────────────────
  const send = (prompt) => window.ember?.sendFollowUpMessage({ prompt }).catch(() => {});
  /** What the widget keeps, by key: merged into widgetState's modelContent so the agent hears it. */
  const keep = (key, value) => {
    const was = window.ember?.widgetState ?? {};
    const modelContent = { ...(was.modelContent ?? {}), [key]: value };
    window.ember?.setWidgetState({ ...was, modelContent }).catch(() => {});
  };
  const kept = (key) => window.ember?.widgetState?.modelContent?.[key];

  define("sf-choices", class extends Base {
    draw() {
      const key = this.id || `choices${[...document.querySelectorAll("sf-choices")].indexOf(this)}`;
      const items = [...this.querySelectorAll(":scope > sf-choice")].map((c) => ({
        title: c.getAttribute("title") ?? c.textContent.trim(), note: c.getAttribute("note"), end: c.getAttribute("end"),
        send: c.getAttribute("send") ?? c.getAttribute("value") ?? c.getAttribute("title") ?? c.textContent.trim(),
      }));
      const chosen = kept(key);
      const rows = items.map((it) => h("button.sf-choice", {
        type: "button", "data-chosen": chosen === it.title || undefined,
        onclick: (e) => {
          for (const r of rows) r.removeAttribute("data-chosen");
          e.currentTarget.setAttribute("data-chosen", "");
          keep(key, it.title);
          send(it.send);
        },
      }, h("span.sf-choice-text", {}, h("span.sf-choice-title", {}, it.title), it.note && h("span.sf-choice-note", {}, it.note)), it.end && h("span.sf-choice-end", {}, it.end)));
      put(this, ...rows);
    }
  });
  define("sf-choice", class extends HTMLElement {});

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
