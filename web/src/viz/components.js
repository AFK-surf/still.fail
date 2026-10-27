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

  /** What a table's or a list's cell shows: text, a number, or {text, status|badge|tone|muted|spark|code}. */
  const cell = (v) => {
    if (v === null || v === undefined) return "";
    if (typeof v === "number") return fmt(v);
    if (typeof v === "boolean") return h("span", { class: v ? "sf-yes" : "sf-no" }, v ? "✓" : "–");
    if (typeof v !== "object") return String(v);
    const text = v.text ?? v.value ?? "";
    if (v.spark) return spark(v.spark, { tone: v.tone });
    if (v.status) return h("sf-status", { tone: v.status }, String(text));
    if (v.badge !== undefined) return h("sf-badge", { tone: v.badge === true ? undefined : v.badge }, String(text));
    if (v.code) return h("code", {}, String(v.code));
    if (v.tone) return h("span", { style: `color:${ink(v.tone)}` }, String(text));
    if (v.muted) return h("span", { style: "color:var(--sf-muted)" }, String(text));
    return String(text);
  };
  const plain = (v) => (v && typeof v === "object" ? v.text ?? v.value : v);

  // ── Table: from data (sortable, searchable), or a <table> inside it ─────────────────
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
      const sortable = this.hasAttribute("sortable");
      const searching = this.getAttribute("search");
      let by = -1, down = false, words = "";
      const body = h("tbody");
      const heads = cols.map((c, i) => h("th", { "data-num": c.num || undefined, "data-sort": sortable ? "" : undefined, onclick: sortable ? () => { down = by === i ? !down : c.num; by = i; fill(); } : undefined }, c.label));
      const fill = () => {
        let list = rows.filter((r) => !words || cols.some((c) => String(plain(at(r, c)) ?? "").toLowerCase().includes(words)));
        if (by >= 0) {
          const c = cols[by];
          list = [...list].sort((x, y) => {
            const a = plain(at(x, c)), b = plain(at(y, c));
            const r = c.num && Number.isFinite(num(a)) && Number.isFinite(num(b)) ? num(a) - num(b) : String(a ?? "").localeCompare(String(b ?? ""));
            return down ? -r : r;
          });
        }
        heads.forEach((th, i) => th.setAttribute("aria-sort", i === by ? (down ? "descending" : "ascending") : "none"));
        put(body, list.map((r) => h("tr", {}, cols.map((c) => h("td", { "data-num": c.num || undefined }, cell(at(r, c)))))));
      };
      fill();
      put(this,
        searching !== null && h("input.form-control.sf-search", { type: "search", placeholder: searching, oninput: (e) => { words = e.target.value.trim().toLowerCase(); fill(); } }),
        h("div.sf-table-scroll", {}, h("table", {}, h("thead", {}, h("tr", {}, heads)), body)));
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
      if (type === "scatter") return this.scatter(d, unit, width);
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

  // ── A list card: rows with a title, a quiet line, what is at their end ───────────────
  const rowOf = (it) => h("div.sf-item", {},
    it.status && h("i.sf-dot", { "data-tone": it.status }),
    h("span.sf-item-text", {}, h("span.sf-item-title", {}, it.title ?? ""), it.note && h("span.sf-item-note", {}, it.note)),
    it.badge && h("sf-badge", { tone: it.tone ?? undefined }, it.badge),
    it.end !== undefined && it.end !== null && h("span.sf-item-end", {}, cell(it.end)));
  define("sf-list", class extends Base {
    draw() {
      const d = dataOf(this);
      const items = d ? (Array.isArray(d) ? d : d.items ?? []) : [...this.querySelectorAll(":scope > sf-item")].map((it) => ({
        title: it.getAttribute("title") ?? it.textContent.trim(), note: it.getAttribute("note"), end: it.getAttribute("end"),
        status: it.getAttribute("status"), badge: it.getAttribute("badge"), tone: it.getAttribute("tone"),
      }));
      put(this, items.map(rowOf));
    }
  });
  define("sf-item", class extends HTMLElement {});

  // ── Options side by side: what each is, its good and bad, the one recommended ringed ─
  define("sf-compare", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      const items = Array.isArray(d) ? d : d.options ?? [];
      put(this, items.map((o) => h("div.sf-option", { "data-recommended": o.recommended || undefined },
        h("div.sf-head", {}, h("div.sf-option-top", {}, h("span.sf-title", {}, o.title ?? ""), o.badge && h("sf-badge", { tone: o.tone ?? undefined }, o.badge)), o.note && h("div.sf-sub", {}, o.note)),
        o.facts && h("sf-facts", { data: JSON.stringify(o.facts) }),
        (o.pros?.length || o.cons?.length) && h("ul.sf-points", {},
          (o.pros ?? []).map((p) => h("li", { "data-good": "" }, p)),
          (o.cons ?? []).map((p) => h("li", { "data-bad": "" }, p))),
        o.send && h("sf-button", { small: true, primary: o.recommended || undefined, send: o.send }, o.action ?? o.title),
      )));
    }
  });

  // ── Code and diffs ──────────────────────────────────────────────────────────────────
  /** An element's text: a `text` attribute, a <script type="text/plain"> inside it, else what it says. */
  const textOf = (el) => {
    const raw = el.getAttribute("text") ?? el.querySelector(":scope > script[type='text/plain'], :scope > template, :scope > pre")?.textContent ?? el.textContent;
    const lines = raw.replace(/\t/g, "  ").replace(/^\n+|\s+$/g, "").split("\n");
    const pad = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length));
    return lines.map((l) => l.slice(Number.isFinite(pad) ? pad : 0));
  };
  const ranges = (spec) => {
    const out = new Set();
    for (const part of String(spec ?? "").split(",")) {
      const [a, b] = part.split("-").map((x) => parseInt(x, 10));
      if (Number.isFinite(a)) for (let i = a; i <= (Number.isFinite(b) ? b : a); i++) out.add(i);
    }
    return out;
  };
  define("sf-code", class extends Base {
    draw() {
      const lines = textOf(this);
      const marked = ranges(this.getAttribute("highlight"));
      const first = num(this.getAttribute("start")) || 1;
      const numbered = !this.hasAttribute("plain");
      const title = this.getAttribute("title") ?? this.getAttribute("lang");
      put(this, h("div.sf-code", {},
        title && h("div.sf-code-title", {}, title),
        h("div.sf-code-body", {}, h("table", {}, h("tbody", {}, lines.map((l, i) => h("tr", { "data-mark": marked.has(first + i) || undefined },
          numbered && h("td.sf-code-n", {}, first + i), h("td.sf-code-line", {}, l || " "))))))));
    }
  });
  define("sf-diff", class extends Base {
    draw() {
      const lines = textOf(this);
      const files = [];
      let file = null, a = 0, b = 0;
      const start = (name) => { file = { name, rows: [], add: 0, del: 0 }; files.push(file); };
      for (const l of lines) {
        if (l.startsWith("diff --git")) { start(l.replace(/^diff --git a\/(.*?) b\/.*$/, "$1")); continue; }
        if (/^(index |new file|deleted file|similarity|rename |old mode|new mode)/.test(l)) continue;
        if (l.startsWith("--- ")) { if (!file) start(""); continue; }
        if (l.startsWith("+++ ")) { const n = l.slice(4).replace(/^b\//, ""); if (file && !file.name && n !== "/dev/null") file.name = n; continue; }
        if (!file) start(this.getAttribute("title") ?? "");
        const m = l.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/);
        if (m) { a = +m[1]; b = +m[2]; file.rows.push({ kind: "hunk", text: m[3].trim() }); continue; }
        if (l.startsWith("+")) { file.rows.push({ kind: "add", n: [null, b++], text: l.slice(1) }); file.add++; }
        else if (l.startsWith("-")) { file.rows.push({ kind: "del", n: [a++, null], text: l.slice(1) }); file.del++; }
        else if (!l.startsWith("\\")) file.rows.push({ kind: "same", n: [a++, b++], text: l.startsWith(" ") ? l.slice(1) : l });
      }
      put(this, files.map((f) => h("div.sf-code", {},
        (f.name || files.length > 1) && h("div.sf-code-title", {}, h("span", {}, f.name), h("span.sf-diff-count", {}, h("span", { "data-add": "" }, `+${f.add}`), " ", h("span", { "data-del": "" }, `−${f.del}`))),
        h("div.sf-code-body", {}, h("table", {}, h("tbody", {}, f.rows.map((r) => r.kind === "hunk"
          ? h("tr.sf-diff-hunk", {}, h("td.sf-code-n", {}), h("td.sf-code-n", {}), h("td.sf-code-line", {}, r.text || "⋯"))
          : h("tr", { "data-kind": r.kind }, h("td.sf-code-n", {}, r.n[0] ?? ""), h("td.sf-code-n", {}, r.n[1] ?? ""), h("td.sf-code-line", {}, r.text || " ")))))))));
    }
  });

  // ── A tree of files (paths), each with a change or a note ───────────────────────────
  const CHANGE = { added: ["A", "green"], add: ["A", "green"], modified: ["M", "amber"], changed: ["M", "amber"], deleted: ["D", "red"], removed: ["D", "red"], renamed: ["R", "blue"] };
  const folderIcon = () => s("svg", { viewBox: "0 0 16 16", width: 14, height: 14, class: "sf-tree-icon" }, s("path", { d: "M2 4.5A1.5 1.5 0 0 1 3.5 3h2.6l1.4 1.5h5A1.5 1.5 0 0 1 14 6v5.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z", fill: "none", stroke: "currentColor", "stroke-width": 1.2 }));
  const fileIcon = () => s("svg", { viewBox: "0 0 16 16", width: 14, height: 14, class: "sf-tree-icon" }, s("path", { d: "M4 2.5h5l3 3v8H4z M9 2.5v3h3", fill: "none", stroke: "currentColor", "stroke-width": 1.2, "stroke-linejoin": "round" }));
  define("sf-tree", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      const root = { kids: new Map() };
      for (const it of Array.isArray(d) ? d : d.files ?? []) {
        const f = typeof it === "string" ? { path: it } : it;
        let node = root;
        const parts = f.path.split("/").filter(Boolean);
        parts.forEach((p, i) => {
          if (!node.kids.has(p)) node.kids.set(p, { name: p, kids: new Map() });
          node = node.kids.get(p);
          if (i === parts.length - 1) Object.assign(node, { file: !f.path.endsWith("/"), note: f.note, change: f.change, end: f.end });
        });
      }
      const rows = [];
      const walk = (node, depth) => {
        const kids = [...node.kids.values()].sort((x, y) => (x.kids.size && !y.kids.size ? -1 : !x.kids.size && y.kids.size ? 1 : x.name.localeCompare(y.name)));
        for (const k of kids) {
          // a folder with one folder in it says both on one row (src/viz)
          let name = k.name, at = k;
          while (at.kids.size === 1 && !at.file && [...at.kids.values()][0].kids.size) { at = [...at.kids.values()][0]; name += `/${at.name}`; }
          const ch = CHANGE[at.change];
          rows.push(h("div.sf-tree-row", { style: `padding-left:${depth * 18}px`, "data-folder": at.kids.size ? "" : undefined },
            at.kids.size ? folderIcon() : fileIcon(), h("span.sf-tree-name", {}, name),
            at.note && h("span.sf-tree-note", {}, at.note), at.end && h("span.sf-tree-end", {}, cell(at.end)),
            ch && h("span.sf-tree-change", { style: `color:${ink(ch[1])}` }, ch[0])));
          walk(at, depth + 1);
        }
      };
      walk(root, 0);
      put(this, rows);
    }
  });

  // ── Timeline: when, what ────────────────────────────────────────────────────────────
  define("sf-timeline", class extends Base {
    draw() {
      const d = dataOf(this);
      const items = d ? (Array.isArray(d) ? d : d.events ?? []) : [...this.querySelectorAll(":scope > sf-event")].map((e) => ({
        time: e.getAttribute("time"), title: e.getAttribute("title") ?? "", note: e.getAttribute("note"), tone: e.getAttribute("tone"), body: [...e.childNodes],
      }));
      put(this, items.map((e) => h("div.sf-event", { "data-tone": e.tone ?? undefined },
        h("span.sf-event-time", {}, e.time ?? ""), h("span.sf-event-mark", { style: e.tone ? `--mark:${ink(e.tone)}` : undefined }),
        h("div.sf-step-body", {}, h("div.sf-step-title", {}, e.title), e.note && h("div.sf-step-note", {}, e.note), e.body))));
    }
  });
  define("sf-event", class extends HTMLElement {});

  // ── Heatmap: a calendar of days, or a grid of rows by columns ───────────────────────
  define("sf-heatmap", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      const unit = this.getAttribute("unit") ?? "";
      const tone = this.getAttribute("tone");
      const color = tone ? ink(tone) : "var(--sf-ink)";
      const shade = (v, max) => (v > 0 ? `color-mix(in srgb, ${color} ${Math.round(18 + 82 * (v / max))}%, transparent)` : "var(--sf-quiet)");
      if (d.rows && d.values) {
        const max = Math.max(1, ...d.values.flat().map(num).filter(Number.isFinite));
        put(this, h("div.sf-heat-grid", { style: `grid-template-columns:max-content repeat(${(d.columns ?? []).length || d.values[0].length},minmax(14px,1fr))` },
          h("span", {}), (d.columns ?? []).map((c) => h("span.sf-heat-col", {}, c)),
          d.rows.map((r, i) => [h("span.sf-heat-row", {}, r), d.values[i].map((v, j) => h("span.sf-heat-cell", { style: `background:${shade(num(v) || 0, max)}`, "data-tooltip": `${r} · ${(d.columns ?? [])[j] ?? j + 1}: ${fmt(num(v))}${unit}` }))])));
        return;
      }
      const days = Object.entries(d.days ?? d).map(([k, v]) => [new Date(`${k}T00:00:00`), num(v) || 0]).filter(([t]) => !Number.isNaN(+t)).sort((x, y) => x[0] - y[0]);
      if (!days.length) return;
      const max = Math.max(1, ...days.map(([, v]) => v));
      const at = new Map(days.map(([t, v]) => [t.toDateString(), v]));
      const from = new Date(days[0][0]);
      from.setDate(from.getDate() - from.getDay());
      const to = days[days.length - 1][0];
      const weeks = [];
      for (let t = new Date(from); t <= to; t.setDate(t.getDate() + 7)) weeks.push(new Date(t));
      const cells = [];
      const months = [];
      weeks.forEach((w, i) => {
        const first = new Date(w);
        for (let k = 0; k < 7; k++) {
          const day = new Date(w);
          day.setDate(day.getDate() + k);
          if (day.getDate() === 1 || (i === 0 && k === 0)) months.push([i, day.toLocaleDateString(undefined, { month: "short" })]);
          const v = at.get(day.toDateString());
          cells.push(h("span.sf-heat-cell", { style: `grid-column:${i + 1};grid-row:${k + 2};background:${day < days[0][0] || day > to ? "transparent" : shade(v ?? 0, max)}`, "data-tooltip": day < days[0][0] || day > to ? undefined : `${day.toLocaleDateString()}: ${fmt(v ?? 0)}${unit}` }));
        }
        void first;
      });
      const seen = new Set();
      put(this, h("div.sf-heat-cal", { style: `grid-template-columns:repeat(${weeks.length},minmax(8px,14px))` },
        months.filter(([i]) => !seen.has(i) && seen.add(i)).map(([i, m]) => h("span.sf-heat-month", { style: `grid-column:${i + 1} / span 4;grid-row:1` }, m)), cells));
    }
  });

  // ── Gantt: tasks along time ─────────────────────────────────────────────────────────
  define("sf-gantt", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      const tasks = Array.isArray(d) ? d : d.tasks ?? [];
      const when = (v) => (typeof v === "number" ? v : +new Date(v));
      const dated = tasks.some((t) => typeof t.start === "string");
      const lo = Math.min(...tasks.map((t) => when(t.start))), hi = Math.max(...tasks.map((t) => when(t.end ?? t.start)));
      const span = hi - lo || 1;
      const at = (v) => ((when(v) - lo) / span) * 100;
      const label = (v) => (dated ? new Date(v).toLocaleDateString(undefined, { month: "numeric", day: "numeric" }) : fmt(v));
      const marks = dated ? [lo, lo + span / 2, hi] : ticks(lo, hi, 4).filter((v) => v >= lo && v <= hi);
      put(this, h("div.sf-gantt", {},
        h("span", {}), h("div.sf-gantt-axis", {}, marks.map((v) => h("span", { style: `left:${((v - lo) / span) * 100}%` }, label(v)))),
        tasks.map((t) => [
          h("span.sf-gantt-name", {}, t.name ?? t.title ?? ""),
          h("div.sf-gantt-track", {}, h("span.sf-gantt-bar", {
            "data-state": t.state ?? undefined, style: `left:${at(t.start)}%;width:max(8px,${at(t.end ?? t.start) - at(t.start)}%)${t.tone ? `;background:${ink(t.tone)}` : ""}`,
            "data-tooltip": `${t.name ?? t.title ?? ""}: ${label(when(t.start))} – ${label(when(t.end ?? t.start))}${t.note ? `\n${t.note}` : ""}`,
          })),
        ])));
    }
  });

  // ── A matrix: what each option has ──────────────────────────────────────────────────
  define("sf-matrix", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      put(this, h("div.sf-table-scroll", {}, h("table.sf-matrix", {},
        h("thead", {}, h("tr", {}, h("th", {}), (d.columns ?? []).map((c) => h("th", {}, c)))),
        h("tbody", {}, (d.rows ?? []).map((r) => h("tr", {}, h("td", {}, Array.isArray(r) ? r[0] : r.label), (Array.isArray(r) ? r.slice(1) : r.values ?? []).map((v) => h("td", {}, v === "partial" || v === null ? h("span.sf-part", {}, "◐") : cell(v)))))))));
    }
  });

  // ── Meter: a measure in cells (a disk, a quota) ─────────────────────────────────────
  define("sf-meter", class extends Base {
    draw() {
      const value = num(this.getAttribute("value")) || 0;
      const max = num(this.getAttribute("max")) || 100;
      const n = num(this.getAttribute("cells")) || 20;
      const full = Math.round(Math.max(0, Math.min(1, value / max)) * n);
      const tone = this.getAttribute("tone");
      put(this,
        h("div.sf-progress-head", {}, h("span", {}, this.getAttribute("label") ?? ""), h("span", {}, this.getAttribute("note") ?? `${fmt(value)} / ${fmt(max)}`)),
        h("div.sf-meter-cells", {}, Array.from({ length: n }, (_, i) => h("i", { "data-on": i < full || undefined, style: i < full && tone ? `background:${ink(tone)}` : undefined }))));
    }
  });

  // ── Before and after: two pictures, a handle between ────────────────────────────────
  define("sf-before-after", class extends Base {
    draw() {
      const before = this.getAttribute("before"), after = this.getAttribute("after");
      const top = h("div.sf-ba-after", {}, h("img", { src: after, alt: this.getAttribute("after-label") ?? "" }));
      const handle = h("span.sf-ba-handle");
      const box = h("div.sf-ba", { style: "--at:50%" }, h("img", { src: before, alt: this.getAttribute("before-label") ?? "" }), top, handle,
        this.getAttribute("before-label") && h("span.sf-ba-label", { "data-side": "before" }, this.getAttribute("before-label")),
        this.getAttribute("after-label") && h("span.sf-ba-label", { "data-side": "after" }, this.getAttribute("after-label")));
      const move = (e) => { const r = box.getBoundingClientRect(); box.style.setProperty("--at", `${Math.max(0, Math.min(100, ((e.clientX - r.left) / r.width) * 100))}%`); };
      box.addEventListener("pointerdown", (e) => { box.setPointerCapture(e.pointerId); move(e); });
      box.addEventListener("pointermove", (e) => { if (box.hasPointerCapture(e.pointerId)) move(e); });
      put(this, box);
    }
  });

  // ── A form whose answers go to the composer ─────────────────────────────────────────
  define("sf-form", class extends Base {
    draw() {
      const key = this.id || `form${[...document.querySelectorAll("sf-form")].indexOf(this)}`;
      const was = kept(key) ?? {};
      const fields = [...this.querySelectorAll(":scope > sf-field")].map((f) => {
        const name = f.getAttribute("label") ?? f.getAttribute("name") ?? "";
        const type = f.getAttribute("type") ?? "text";
        const options = (f.getAttribute("options") ?? "").split("|").filter(Boolean);
        const value = was[name] ?? f.getAttribute("value") ?? (type === "choice" ? options[0] : "");
        let input;
        let read;
        if (type === "choice") {
          let chosen = value;
          const bar = h("div.sf-segmented", {}, options.map((o) => h("button.sf-segment", { type: "button", "aria-selected": String(o === chosen), onclick: (e) => { chosen = o; for (const b of bar.children) b.setAttribute("aria-selected", String(b === e.currentTarget)); } }, o)));
          input = bar;
          read = () => chosen;
        } else if (type === "select") {
          input = h("select.form-select", {}, options.map((o) => h("option", { selected: o === value || undefined }, o)));
          read = () => input.value;
        } else if (type === "textarea") {
          input = h("textarea.form-control", { placeholder: f.getAttribute("placeholder") ?? undefined, rows: 3 });
          input.value = value;
          read = () => input.value.trim();
        } else if (type === "check") {
          const box = h("input.form-check-input", { type: "checkbox", checked: value === true || value === "true" || f.hasAttribute("checked") || undefined });
          input = h("label.form-check", {}, box, h("span.form-check-label", {}, f.getAttribute("text") ?? name));
          read = () => box.checked;
        } else {
          input = h("input.form-control", { type: type === "number" ? "number" : "text", placeholder: f.getAttribute("placeholder") ?? undefined, min: f.getAttribute("min") ?? undefined, max: f.getAttribute("max") ?? undefined });
          input.value = value;
          read = () => input.value.trim();
        }
        return { name, type, read, el: h("label.sf-field", {}, type !== "check" && h("span.form-label", {}, name), input, f.getAttribute("note") && h("span.sf-sub", {}, f.getAttribute("note"))) };
      });
      const submit = () => {
        const answers = Object.fromEntries(fields.map((f) => [f.name, f.read()]));
        keep(key, answers);
        const intro = this.getAttribute("intro");
        const lines = fields.map((f) => { const v = answers[f.name]; return f.type === "check" ? `${f.name}: ${v ? "✓" : "✗"}` : v === "" ? null : `${f.name}: ${v}`; }).filter(Boolean);
        send([intro, ...lines].filter(Boolean).join("\n"));
      };
      put(this, fields.map((f) => f.el), h("div.sf-form-foot", {}, h("button.sf-button", { type: "button", "data-primary": "", onclick: submit }, this.getAttribute("submit") ?? "OK")));
    }
  });
  define("sf-field", class extends HTMLElement {});

  // ── A section that opens ────────────────────────────────────────────────────────────
  define("sf-details", class extends Base {
    draw() {
      const body = h("div.sf-details-body", {}, ...this.childNodes);
      const d = h("details", { open: this.hasAttribute("open") || undefined }, h("summary", {}, h("span", {}, this.getAttribute("summary") ?? ""), this.getAttribute("note") && h("span.sf-sub", {}, this.getAttribute("note"))), body);
      put(this, d);
    }
  });

  // ── Board: columns of cards ─────────────────────────────────────────────────────────
  define("sf-board", class extends Base {
    draw() {
      const d = dataOf(this);
      if (!d) return;
      put(this, (Array.isArray(d) ? d : d.columns ?? []).map((c) => h("div.sf-board-col", {},
        h("div.sf-board-head", {}, h("span", {}, c.title ?? ""), h("span.sf-board-count", {}, (c.items ?? []).length)),
        (c.items ?? []).map((it) => h("div.sf-board-card", {},
          h("div.sf-item-title", {}, it.status && h("i.sf-dot", { "data-tone": it.status }), it.title ?? ""),
          it.note && h("div.sf-item-note", {}, it.note),
          (it.badge || it.end) && h("div.sf-board-foot", {}, it.badge && h("sf-badge", { tone: it.tone ?? undefined }, it.badge), it.end && h("span.sf-item-end", {}, it.end)))))));
    }
  });
})();
