// still.fail's charts (<viz-chart>, <viz-spark>) as the app draws them in a visualization of its own (viz_native.mbt):
// the same marks the page's script makes (web/src/viz/components.js), written as the HTML and SVG it would put in
// their place, in the tokens' colours (var(--…)), then drawn as the rest of the figure is. `width`: the room the
// figure has, the chart's width as the page's ResizeObserver would give it.

///|
fn chart_num(j : Json?) -> Double? {
  match j {
    Some(Number(n, ..)) => Some(n)
    Some(String(s)) => {
      let t = s.replace_all(old=",", new="").replace_all(old="_", new="").trim().to_string()
      if t == "" {
        None
      } else {
        @html.parse_number(t)
      }
    }
    _ => None
  }
}

///|
fn chart_str(j : Json?) -> String {
  match j {
    Some(String(s)) => s
    Some(Number(n, ..)) => chart_fmt(n, 2)
    _ => ""
  }
}

///|
/// A number as toLocaleString writes it in English: thousands grouped, at most `digits` after the point.
fn chart_fmt(n : Double, digits : Int) -> String {
  if n.is_nan() || n.is_inf() {
    return n.to_string()
  }
  let neg = n < 0.0
  let scale = @dmath.pow(10.0, digits.to_double())
  let r = (n.abs() * scale).round() / scale
  let whole = r.floor()
  let frac = r - whole
  let ws = whole.to_int64().to_string()
  let b = StringBuilder()
  let len = ws.length()
  for i in 0..<len {
    if i > 0 && (len - i) % 3 == 0 {
      b.write_char(',')
    }
    b.write_char(Int::unsafe_to_char(ws.code_unit_at(i).to_int()))
  }
  if digits > 0 && frac > 0.0 {
    let f = (frac * scale).round().to_int64().to_string()
    let padded = "0".repeat(digits - f.length()) + f
    let trimmed = padded.trim_end(chars="0").to_string()
    if trimmed != "" {
      b.write_char('.')
      b.write_string(trimmed)
    }
  }
  let s = b.to_string()
  if neg && s != "0" {
    "-" + s
  } else {
    s
  }
}

///|
fn chart_short(n : Double) -> String {
  let a = n.abs()
  if a >= 1.0e9 {
    chart_fmt(n / 1.0e9, 1) + "B"
  } else if a >= 1.0e6 {
    chart_fmt(n / 1.0e6, 1) + "M"
  } else if a >= 1.0e4 {
    chart_fmt(n / 1.0e3, 1) + "k"
  } else {
    chart_fmt(n, 2)
  }
}

///|
/// Round steps for an axis from the least to the most (components.js ticks).
fn chart_ticks(lo0 : Double, hi0 : Double) -> Array[Double] {
  let lo = lo0
  let hi = if hi0 == lo0 { lo0 + 1.0 } else { hi0 }
  let raw = (hi - lo) / 4.0
  let mag = @dmath.pow(10.0, (@dmath.log10(raw)).floor())
  let mut step = raw
  for m in [1.0, 2.0, 2.5, 5.0, 10.0] {
    if m * mag >= raw {
      step = m * mag
      break
    }
  }
  let start = (lo / step).floor() * step
  let out = []
  let mut v = start
  while v <= hi + step * 1.0e-9 && out.length() < 50 {
    out.push((v * 1.0e9).round() / 1.0e9)
    v = v + step
  }
  if out.is_empty() || out[out.length() - 1] < hi {
    let last = if out.is_empty() { start } else { out[out.length() - 1] }
    out.push(((last + step) * 1.0e9).round() / 1.0e9)
  }
  out
}

///|
/// A tone's token (components.js TONE_INK).
fn chart_tone(tone : String) -> String? {
  match tone {
    "green" | "ok" => Some("--green")
    "yellow" | "amber" | "warn" => Some("--yellow")
    "red" | "error" => Some("--red")
    "blue" | "info" => Some("--blue")
    "purple" => Some("--purple")
    "orange" => Some("--orange")
    "ink" => Some("--foreground")
    "muted" => Some("--muted-foreground")
    _ => None
  }
}

///|
fn chart_ink(tone : String, i : Int) -> String {
  match chart_tone(tone) {
    Some(v) => "var(" + v + ")"
    None => "var(--viz-series-" + (i % 6 + 1).to_string() + ")"
  }
}

///|
fn chart_esc(s : String) -> String {
  s.replace_all(old="&", new="&amp;").replace_all(old="<", new="&lt;").replace_all(old="\"", new="&quot;")
}

///|
fn n2(v : Double) -> String {
  let r = (v * 100.0).round() / 100.0
  if r == r.floor() {
    r.to_int().to_string()
  } else {
    r.to_string()
  }
}

///|
/// The element's data: its `data` attribute, else a <script type="application/json"> in it.
fn chart_data(e : @html.Elem) -> Json? {
  let raw = match e.attr("data") {
    Some(d) => d
    None => {
      let mut found = ""
      for k in e.kids {
        if k is Elem(s) && s.tag == "script" {
          found = s.text()
        }
      }
      found
    }
  }
  if raw == "" {
    return None
  }
  Some(@json.parse(raw) catch { _ => return None })
}

///|
fn chart_field(j : Json?, key : String) -> Json? {
  match j {
    Some(Object(o)) => o.get(key)
    _ => None
  }
}

///|
fn chart_array(j : Json?) -> Array[Json] {
  match j {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// What a still.fail chart element stands for in HTML (None: not one of them).
fn viz_chart_html(e : @html.Elem, width : Double) -> String? {
  match e.tag {
    "viz-spark" => Some(viz_spark_html(e))
    "viz-chart" => {
      let w = if width > 0.0 { width.round() } else { 600.0 }
      Some("<viz-chart class=\"" + e.attr("class").unwrap_or("") + "\">" + viz_chart_inner(e, w) + "</viz-chart>")
    }
    _ => None
  }
}

///|
fn viz_spark_html(e : @html.Elem) -> String {
  let raw = e.attr("data").unwrap_or(e.text())
  let values : Array[Double] = match (@json.parse(raw) catch { _ => Json::null() }) {
    Array(a) => a.filter_map(fn(x) { chart_num(Some(x)) })
    _ => @html.split_words(raw.replace_all(old=",", new=" ")).filter_map(fn(x) { @html.parse_number(x) })
  }
  let w = e.attr("width").bind(@html.parse_number).unwrap_or(80.0)
  let h = e.attr("height").bind(@html.parse_number).unwrap_or(20.0)
  let tone = e.attr("tone")
  let b = StringBuilder()
  b.write_string("<viz-spark><svg class=\"viz-spark\" viewBox=\"0 0 \{n2(w)} \{n2(h)}\" preserveAspectRatio=\"none\" width=\"\{n2(w)}\" height=\"\{n2(h)}\">")
  if values.length() >= 2 {
    let lo = values.fold(init=values[0], fn(a, x) { if x < a { x } else { a } })
    let hi0 = values.fold(init=values[0], fn(a, x) { if x > a { x } else { a } })
    let hi = if hi0 == lo { lo + 1.0 } else { hi0 }
    let pts = values.mapi(fn(i, v) {
      n2(i.to_double() / (values.length() - 1).to_double() * w) + "," + n2(2.0 + (1.0 - (v - lo) / (hi - lo)) * (h - 4.0))
    })
    let stroke = match tone {
      Some(t) => chart_ink(t, 0)
      None => "var(--viz-series-1)"
    }
    b.write_string("<polyline points=\"" + pts.join(" ") + "\" fill=\"none\" stroke=\"" + stroke + "\" stroke-width=\"1.5\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>")
  }
  b.write_string("</svg></viz-spark>")
  b.to_string()
}

///|
fn viz_chart_inner(e : @html.Elem, width : Double) -> String {
  let d = chart_data(e)
  if d is None {
    return "<p class=\"text-small text-muted\">viz-chart: its data is not JSON</p>"
  }
  let ty = e.attr("type").unwrap_or("bar")
  let unit = chart_esc(e.attr("unit").unwrap_or(""))
  let title = match e.attr("title") {
    Some(t) if t != "" => "<div class=\"viz-chart-title\">" + chart_esc(t) + "</div>"
    _ => ""
  }
  match ty {
    "donut" | "pie" => title + chart_donut(e, d, unit, ty == "pie")
    "hbar" => title + chart_hbar(e, d, unit)
    "scatter" => title + chart_scatter(e, d, unit, width)
    _ => title + chart_xy(e, d, unit, width, ty)
  }
}

///|
fn chart_items(d : Json?) -> Array[(String, Double, String, String)] {
  let items = chart_array(chart_field(d, "items"))
  if !items.is_empty() {
    return items.map(fn(it) {
      let o = Some(it)
      (chart_str(chart_field(o, "label")), chart_num(chart_field(o, "value")).unwrap_or(0.0), chart_str(chart_field(o, "tone")), chart_str(chart_field(o, "note")))
    })
  }
  let labels = chart_array(chart_field(d, "labels"))
  let values = chart_array(chart_field(d, "values"))
  labels.mapi(fn(i, l) { (chart_str(Some(l)), chart_num(values.get(i)).unwrap_or(0.0), "", "") })
}

///|
fn chart_legend(entries : Array[(String, String)], round : Bool) -> String {
  if entries.length() < 2 {
    return ""
  }
  let b = StringBuilder()
  b.write_string("<div class=\"viz-chart-legend\">")
  for en in entries {
    b.write_string("<span><i style=\"background:" + en.1 + (if round { ";border-radius:50%" } else { "" }) + "\"></i>" + chart_esc(en.0) + "</span>")
  }
  b.write_string("</div>")
  b.to_string()
}

///|
fn chart_xy(e : @html.Elem, d : Json?, unit : String, width : Double, ty : String) -> String {
  let labels = chart_array(chart_field(d, "labels")).map(fn(l) { chart_str(Some(l)) })
  let series_json = chart_array(chart_field(d, "series"))
  let series : Array[(String, Array[Double?], String)] = if series_json.is_empty() {
    [(chart_str(chart_field(d, "name")), chart_array(chart_field(d, "values")).map(fn(v) { chart_num(Some(v)) }), chart_ink(chart_str(chart_field(d, "tone")), 0))]
  } else {
    series_json.mapi(fn(i, sr) {
      let o = Some(sr)
      (chart_str(chart_field(o, "name")), chart_array(chart_field(o, "values")).map(fn(v) { chart_num(Some(v)) }), chart_ink(chart_str(chart_field(o, "tone")), i))
    })
  }
  let stacked = e.has("stacked") && ty == "bar"
  let height = e.attr("height").bind(@html.parse_number).unwrap_or(200.0)
  let all : Array[Double] = if stacked {
    labels.mapi(fn(i, _) { series.fold(init=0.0, fn(a, sr) { a + sr.1.get(i).unwrap_or(None).unwrap_or(0.0) }) })
  } else {
    let out = []
    for sr in series {
      for v in sr.1 {
        if v is Some(x) {
          out.push(x)
        }
      }
    }
    out
  }
  let lo = all.fold(init=0.0, fn(a, x) { if x < a { x } else { a } })
  let hi = all.fold(init=0.0, fn(a, x) { if x > a { x } else { a } })
  let ys = chart_ticks(lo, hi)
  let y0 = ys[0]
  let y1 = ys[ys.length() - 1]
  let label_w = ys.fold(init=0.0, fn(m, v) { let l = chart_label_w(chart_short(v) + unit); if l > m { l } else { m } }) + 12.0
  let left = label_w
  let right = 4.0
  let top = 8.0
  let bottom = 22.0
  let plot_w = if width - left - right > 40.0 { width - left - right } else { 40.0 }
  let plot_h = height - top - bottom
  let y_of = fn(v : Double) { top + plot_h - (v - y0) / (y1 - y0) * plot_h }
  let b = StringBuilder()
  b.write_string("<svg viewBox=\"0 0 \{n2(width)} \{n2(height)}\" height=\"\{n2(height)}\" role=\"img\">")
  for v in ys {
    let y = n2(y_of(v))
    b.write_string("<line class=\"viz-chart-grid\" x1=\"\{n2(left)}\" x2=\"\{n2(width - right)}\" y1=\"\{y}\" y2=\"\{y}\"/>")
    b.write_string("<text class=\"viz-chart-axis\" x=\"\{n2(left - 8.0)}\" y=\"\{y}\" text-anchor=\"end\" dominant-baseline=\"middle\">" + chart_short(v) + unit + "</text>")
  }
  let n = if labels.length() > 1 { labels.length() } else { 1 }
  let band = plot_w / n.to_double()
  let longest = labels.fold(init=0, fn(m, l) { if l.length() > m { l.length() } else { m } })
  let every = {
    let k = ((longest.to_double() * 6.5 + 12.0) / band).ceil().to_int()
    if k < 1 {
      1
    } else {
      k
    }
  }
  let x_of = fn(i : Int) {
    if n == 1 {
      left + plot_w / 2.0
    } else {
      left + plot_w * i.to_double() / (n - 1).to_double()
    }
  }
  for i, l in labels {
    if i % every != 0 {
      continue
    }
    let x = if ty == "bar" { left + band * (i.to_double() + 0.5) } else { x_of(i) }
    let anchor = if n > 1 && ty != "bar" && i == 0 { "start" } else if n > 1 && ty != "bar" && i == n - 1 { "end" } else { "middle" }
    b.write_string("<text class=\"viz-chart-axis\" x=\"\{n2(x)}\" y=\"\{n2(height - 6.0)}\" text-anchor=\"\{anchor}\">" + chart_esc(l) + "</text>")
  }
  if ty == "bar" {
    let inner = band * 0.72
    let count = series.length().to_double()
    let each = if stacked { inner } else { inner / count }
    let r = if each / 4.0 < 4.0 { each / 4.0 } else { 4.0 }
    for i in 0..<labels.length() {
      let mut acc = 0.0
      for k, sr in series {
        let v = sr.1.get(i).unwrap_or(None).unwrap_or(0.0)
        let x = left + band * i.to_double() + (band - inner) / 2.0 + (if stacked { 0.0 } else { each * k.to_double() })
        let from = if stacked { acc } else { 0.0 }
        acc = acc + v
        let ya = y_of(if from > from + v { from } else { from + v })
        let yb = y_of(if from < from + v { from } else { from + v })
        let w = {
          let x = each - (if stacked || series.length() == 1 { 0.0 } else { 2.0 })
          if x < 1.0 {
            1.0
          } else {
            x
          }
        }
        let hgt = {
          let least = if v == 0.0 { 0.0 } else { 1.0 }
          if yb - ya > least {
            yb - ya
          } else {
            least
          }
        }
        let top_ = !stacked || k == series.length() - 1
        let path = if top_ && hgt > r {
          "M\{n2(x)},\{n2(ya + hgt)}V\{n2(ya + r)}Q\{n2(x)},\{n2(ya)} \{n2(x + r)},\{n2(ya)}H\{n2(x + w - r)}Q\{n2(x + w)},\{n2(ya)} \{n2(x + w)},\{n2(ya + r)}V\{n2(ya + hgt)}Z"
        } else {
          "M\{n2(x)},\{n2(ya)}h\{n2(w)}v\{n2(hgt)}h\{n2(-w)}Z"
        }
        b.write_string("<path d=\"" + path + "\" fill=\"" + sr.2 + "\"/>")
      }
    }
  } else {
    let base = y_of(if y0 > 0.0 { y0 } else { 0.0 })
    for sr in series {
      let pts = []
      for i, v in sr.1 {
        if v is Some(x) {
          pts.push((x_of(i), y_of(x)))
        }
      }
      if pts.is_empty() {
        continue
      }
      let line = StringBuilder()
      for i, p in pts {
        line.write_string((if i == 0 { "M" } else { "L" }) + n2(p.0) + "," + n2(p.1))
      }
      let l = line.to_string()
      if ty == "area" {
        let op = if series.length() > 1 { "0.12" } else { "0.16" }
        b.write_string("<path d=\"" + l + "L" + n2(pts[pts.length() - 1].0) + "," + n2(base) + "L" + n2(pts[0].0) + "," + n2(base) + "Z\" fill=\"" + sr.2 + "\" fill-opacity=\"" + op + "\"/>")
      }
      b.write_string("<path d=\"" + l + "\" fill=\"none\" stroke=\"" + sr.2 + "\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>")
      if pts.length() <= 24 {
        for p in pts {
          b.write_string("<circle cx=\"" + n2(p.0) + "\" cy=\"" + n2(p.1) + "\" r=\"3\" fill=\"" + sr.2 + "\"/>")
        }
      }
    }
  }
  b.write_string("</svg>")
  b.to_string() + chart_legend(series.map(fn(sr) { (sr.0, sr.2) }), false)
}

///|
fn chart_hbar(e : @html.Elem, d : Json?, unit : String) -> String {
  let items = chart_items(d)
  let most = items.fold(init=0.0, fn(m, it) { if it.1 > m { it.1 } else { m } })
  let max = match e.attr("max").bind(@html.parse_number) {
    Some(m) if m > 0.0 => m
    _ => if most > 0.0 { most } else { 1.0 }
  }
  let b = StringBuilder()
  b.write_string("<div class=\"viz-hbars\">")
  for it in items {
    let share = {
      let k = it.1 / max * 100.0
      if k < 0.0 {
        0.0
      } else if k > 100.0 {
        100.0
      } else {
        k
      }
    }
    let color = if it.2 != "" { chart_ink(it.2, 0) } else { "var(--viz-series-1)" }
    b.write_string("<span class=\"viz-bar-label\">" + chart_esc(it.0) + "</span>")
    b.write_string("<span class=\"viz-bar-track\"><span class=\"viz-bar-fill\" style=\"width:" + n2(share) + "%;background:" + color + "\"></span></span>")
    b.write_string("<span class=\"viz-bar-value\">" + (if it.3 != "" { chart_esc(it.3) } else { chart_fmt(it.1, 2) + unit }) + "</span>")
  }
  b.write_string("</div>")
  b.to_string()
}

///|
fn chart_donut(e : @html.Elem, d : Json?, unit : String, pie : Bool) -> String {
  let items = chart_items(d)
  let sum = items.fold(init=0.0, fn(a, it) { a + it.1 })
  let total = if sum == 0.0 { 1.0 } else { sum }
  let big_r = 60.0
  let r = if pie { 0.0 } else { 42.0 }
  let c = 70.0
  let pi = 3.141592653589793
  let b = StringBuilder()
  b.write_string("<div class=\"viz-chart-donut\"><svg viewBox=\"0 0 140 140\" role=\"img\">")
  let mut a = -pi / 2.0
  let colors = []
  for i, it in items {
    let span = it.1 / total * pi * 2.0
    let color = chart_ink(it.2, i)
    colors.push(color)
    let end = a + span
    let big = if span > pi { 1 } else { 0 }
    let p = fn(rad : Double, ang : Double) { n2(c + rad * @dmath.cos(ang)) + "," + n2(c + rad * @dmath.sin(ang)) }
    let gap = if items.length() > 1 { 0.012 } else { 0.0 }
    let path = if span >= pi * 2.0 - 1.0e-6 {
      "M\{n2(c - big_r)},\{n2(c)}a\{n2(big_r)},\{n2(big_r)} 0 1,0 \{n2(big_r * 2.0)},0a\{n2(big_r)},\{n2(big_r)} 0 1,0 \{n2(-big_r * 2.0)},0" +
      (if r > 0.0 { "M\{n2(c - r)},\{n2(c)}a\{n2(r)},\{n2(r)} 0 1,1 \{n2(r * 2.0)},0a\{n2(r)},\{n2(r)} 0 1,1 \{n2(-r * 2.0)},0" } else { "" }) +
      "Z"
    } else {
      "M" + p(big_r, a + gap) + "A\{n2(big_r)},\{n2(big_r)} 0 \{big},1 " + p(big_r, end - gap) +
      (if r > 0.0 { "L" + p(r, end - gap) + "A\{n2(r)},\{n2(r)} 0 \{big},0 " + p(r, a + gap) } else { "L\{n2(c)},\{n2(c)}" }) +
      "Z"
    }
    b.write_string("<path d=\"" + path + "\" fill=\"" + color + "\" fill-rule=\"evenodd\"/>")
    a = end
  }
  let center = e.attr("center")
  if r > 0.0 && center != Some("") {
    let words = match center {
      Some(t) => chart_esc(t)
      None => chart_short(sum) + unit
    }
    b.write_string("<text class=\"viz-chart-center\" x=\"70\" y=\"70\" text-anchor=\"middle\" dominant-baseline=\"central\">" + words + "</text>")
  }
  b.write_string("</svg><div class=\"viz-chart-legend\">")
  for i, it in items {
    b.write_string("<span><span style=\"display:inline-flex;align-items:center;gap:6px\"><i style=\"background:" + colors[i] + "\"></i>" + chart_esc(it.0) + "</span><b>" + chart_fmt(it.1, 2) + unit + "</b></span>")
  }
  b.write_string("</div></div>")
  b.to_string()
}

///|
fn chart_scatter(e : @html.Elem, d : Json?, unit : String, width : Double) -> String {
  let series_json = chart_array(chart_field(d, "series"))
  let series : Array[(String, Array[(Double, Double)], String)] = (if series_json.is_empty() {
    [Json::object({ "name": chart_field(d, "name").unwrap_or(Json::string("")), "points": chart_field(d, "points").unwrap_or(Json::array([])) })]
  } else {
    series_json
  }).mapi(fn(i, sr) {
    let o = Some(sr)
    let pts = chart_array(chart_field(o, "points")).filter_map(fn(p) {
      let x = match p {
        Array(a) => chart_num(a.get(0))
        _ => chart_num(chart_field(Some(p), "x"))
      }
      let y = match p {
        Array(a) => chart_num(a.get(1))
        _ => chart_num(chart_field(Some(p), "y"))
      }
      match (x, y) {
        (Some(x), Some(y)) => Some((x, y))
        _ => None
      }
    })
    (chart_str(chart_field(o, "name")), pts, chart_ink(chart_str(chart_field(o, "tone")), i))
  })
  let all = series.fold(init=[], fn(acc : Array[(Double, Double)], sr) { acc + sr.1 })
  if all.is_empty() {
    return ""
  }
  let height = e.attr("height").bind(@html.parse_number).unwrap_or(220.0)
  let min = fn(xs : Array[Double]) { xs.fold(init=xs[0], fn(a, x) { if x < a { x } else { a } }) }
  let max = fn(xs : Array[Double]) { xs.fold(init=xs[0], fn(a, x) { if x > a { x } else { a } }) }
  let px = all.map(fn(p) { p.0 })
  let py = all.map(fn(p) { p.1 })
  let xs = chart_ticks(min(px), max(px))
  let ys = chart_ticks(if min(py) < 0.0 { min(py) } else { 0.0 }, max(py))
  let xunit = chart_esc(e.attr("x-unit").unwrap_or(""))
  let left = ys.fold(init=0.0, fn(m, v) { let l = chart_label_w(chart_short(v) + unit); if l > m { l } else { m } }) + 12.0
  let right = 8.0
  let top = 8.0
  let bottom = 22.0
  let pw = width - left - right
  let ph = height - top - bottom
  let x_of = fn(v : Double) { left + (v - xs[0]) / (xs[xs.length() - 1] - xs[0]) * pw }
  let y_of = fn(v : Double) { top + ph - (v - ys[0]) / (ys[ys.length() - 1] - ys[0]) * ph }
  let b = StringBuilder()
  b.write_string("<svg viewBox=\"0 0 \{n2(width)} \{n2(height)}\" height=\"\{n2(height)}\" role=\"img\">")
  for v in ys {
    let y = n2(y_of(v))
    b.write_string("<line class=\"viz-chart-grid\" x1=\"\{n2(left)}\" x2=\"\{n2(width - right)}\" y1=\"\{y}\" y2=\"\{y}\"/>")
    b.write_string("<text class=\"viz-chart-axis\" x=\"\{n2(left - 8.0)}\" y=\"\{y}\" text-anchor=\"end\" dominant-baseline=\"middle\">" + chart_short(v) + unit + "</text>")
  }
  for i, v in xs {
    let anchor = if i == 0 { "start" } else if i == xs.length() - 1 { "end" } else { "middle" }
    b.write_string("<text class=\"viz-chart-axis\" x=\"\{n2(x_of(v))}\" y=\"\{n2(height - 6.0)}\" text-anchor=\"\{anchor}\">" + chart_short(v) + xunit + "</text>")
  }
  for sr in series {
    for p in sr.1 {
      b.write_string("<circle cx=\"\{n2(x_of(p.0))}\" cy=\"\{n2(y_of(p.1))}\" r=\"4\" fill=\"" + sr.2 + "\" fill-opacity=\"0.85\"/>")
    }
  }
  b.write_string("</svg>")
  b.to_string() + chart_legend(series.map(fn(sr) { (sr.0, sr.2) }), true)
}

///|
/// How wide an axis label is at least, in points at 11-point words: a digit's width, wider for letters and a CJK
/// character's whole em (taken generously: a label cut off at the plot's left is worse than a little more room).
fn chart_label_w(t : String) -> Double {
  let mut w = 0.0
  for c in t {
    let k = c.to_int()
    w += if k >= 0x2E80 {
      11.0
    } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '%' {
      if c == 'm' || c == 'w' || c == 'M' || c == 'W' || c == '%' { 9.5 } else { 7.0 }
    } else {
      6.8
    }
  }
  w
}
