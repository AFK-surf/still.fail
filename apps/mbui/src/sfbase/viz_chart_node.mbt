// Native chart & SVG primitives for declarative `.mbui` widgets.
//
// Renders bar, stacked-bar, line, area, horizontal-bar (hbar), donut/pie, scatter, and sparkline charts
// directly inside the `mbui` layout tree using native `@view.View` and `@ui.Ctx` boxes, `@sf.progress_node`,
// and theme tokens (`@sf.theme().p` and `@sf.usage_series`) with zero bitmap/SVG decode overhead for charts.

///|
priv struct VizSeries {
  name : String
  values : Array[Double]
  color : String
}

///|
priv struct VizHBarItem {
  label : String
  value : Double
  text : String
  color : String
}

///|
priv struct VizPieSlice {
  label : String
  value : Double
  color : String
}

///|
priv struct VizChart {
  kind : String
  title : String
  subtitle : String
  center : String
  labels : Array[String]
  series : Array[VizSeries]
  items : Array[VizHBarItem]
  slices : Array[VizPieSlice]
  min : Double?
  max : Double?
  unit : String
  height : Double
  stacked : Bool
  show_legend : Bool
  show_grid : Bool
  reference : Double?
  reference_label : String
}

///|
fn viz_fixed_len(v : Double) -> @ui.Len {
  Fixed(v)
}

///|
// kept across runs: a value (no field of it changes)
let viz_legend_dot_side : @ui.Len = viz_fixed_len(8.0)

///|
// kept across runs: a value (no field of it changes)
let viz_bar_col_w : @ui.Len = viz_fixed_len(18.0)

///|
// kept across runs: a value (no field of it changes)
let viz_bar_single_w : @ui.Len = viz_fixed_len(26.0)

///|
// kept across runs: a value (no field of it changes)
let viz_line_Line_h : @ui.Len = viz_fixed_len(1.0)

///|
// kept across runs: a value (no field of it changes)
let viz_pie_track_h : @ui.Len = viz_fixed_len(12.0)

///|
// kept across runs: a value (no field of it changes)
let viz_col_s2 : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let viz_col_s1 : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let viz_col_s0_5 : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let viz_row_between_s2 : @ui.Style = @ui.css("row w=Full justify=JBetween align=ACenter gap=S2")

///|
// kept across runs: a value (no field of it changes)
let viz_legend_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let viz_legend_item : @ui.Style = @ui.css("row gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let viz_axis_row : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let viz_axis_cell : @ui.Style = @ui.style(w=@sf.grow, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let viz_plot_row : @ui.Style = @ui.css("row w=Full align=AEnd gap=S2 pt=S1")

///|
// kept across runs: a value (no field of it changes)
let viz_cat_col : @ui.Style = @ui.style(w=@sf.grow, align=ACenter, justify=JEnd, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let viz_bar_group_row : @ui.Style = @ui.css("row align=AEnd justify=JCenter gap=S1")

///|
// kept across runs: a value (no field of it changes)
let viz_bar_item_col : @ui.Style = @ui.css("align=ACenter justify=JEnd gap=S0_5")

///|
fn viz_svg_hex(color : Int64) -> String {
  let ground = @sf.theme().p.card
  mermaid_hex(color, ground)
}

///|
fn viz_tone_color(tone : String, idx : Int) -> Int64 {
  let p = @sf.theme().p
  match @sf.lower(tone.trim().to_owned()) {
    "" => @sf.usage_series(idx)
    "accent" | "orange" | "primary" | "brand" => p.accent
    "green" | "good" | "success" | "ok" | "emerald" => p.green
    "amber" | "warn" | "warning" | "yellow" => p.warn_ink
    "red" | "bad" | "danger" | "error" | "rose" => p.red
    "blue" | "info" | "cyan" => p.blue
    "purple" | "violet" | "indigo" => @sf.usage_series(4)
    "muted" | "neutral" | "gray" | "grey" | "secondary" => p.muted
    "ink" | "text" => p.text
    s =>
      match @sf.hex_color(s) {
        Some(c) => c
        None => @sf.usage_series(idx)
      }
  }
}

///|
fn viz_fmt_num(v : Double, unit : String) -> String {
  let abs_v = v.abs()
  let num_str = if (v - v.round()).abs() < 0.005 {
    v.round().to_int().to_string()
  } else if abs_v >= 100.0 {
    ((v * 10.0).round() / 10.0).to_string()
  } else {
    ((v * 100.0).round() / 100.0).to_string()
  }
  if unit == "" {
    num_str
  } else if unit == "%" || unit == "ms" || unit == "s" || unit == "x" || unit == "B" || unit == "KB" || unit == "MB" || unit == "GB" {
    num_str + unit
  } else {
    num_str + " " + unit
  }
}

///|
fn viz_register_svg(prefix : String, svg : String, max_px? : Int = 640) -> String {
  ignore(max_px)
  let dark_tag = if @sf.theme().dark { "d" } else { "l" }
  let key = "mem:viz-svg/" + prefix + "/" + dark_tag + "/\{@ui.stable_hash(svg)}/\{svg.length()}"
  @ui.add_image(key, @utf8.encode(svg))
  key
}

///|
fn viz_svg_ctx(c : @ui.Ctx, key_prefix : String, svg : String, w : Double, h : Double) -> Unit {
  let w_safe = if w > 1.0 { w } else { 400.0 }
  let h_safe = if h > 1.0 { h } else { 180.0 }
  let pic = viz_register_svg(key_prefix, svg, max_px=640)
  c.box(style=@ui.style(w=Full, max_w=viz_fixed_len(w_safe)), aspect=w_safe / h_safe, fn() {
    c.image(pic, w=Fill(1.0), h=Fill(1.0), fit=FitContain, bg=0L, fade=false) |> ignore
  })
  |> ignore
}

///|
fn viz_svg_node(parent : @view.View, key_prefix : String, svg : () -> (String, Double, Double), in_row? : Bool = false) -> Unit {
  parent.box(fn(b) {
    @sf.style_node(
      b,
      fn() {
        let (_, w, _) = svg()
        let w_safe = if w > 1.0 { w } else { 400.0 }
        @ui.style(w=Full, max_w=viz_fixed_len(w_safe))
      },
      in_row~,
    )
    b
    .aspect(
      By(fn() {
        let (_, w, h) = svg()
        let w_safe = if w > 1.0 { w } else { 400.0 }
        let h_safe = if h > 1.0 { h } else { 180.0 }
        w_safe / h_safe
      }),
    )
    .image(
      By(fn() {
        let (s, _, _) = svg()
        if s == "" {
          None
        } else {
          Some((viz_register_svg(key_prefix, s, max_px=640), "", 640))
        }
      }),
    )
    .image_contains(Is(true))
    |> ignore
  })
  |> ignore
}

///|
fn viz_spark_bars(values : Array[Double], h : Double) -> Array[Double] {
  let n = values.length()
  if n == 0 {
    return []
  }
  let mut lo = values[0]
  let mut hi = values[0]
  for v in values {
    if v < lo {
      lo = v
    }
    if v > hi {
      hi = v
    }
  }
  let max_h = @sf.dmax(8.0, h - 2.0)
  let out : Array[Double] = []
  if hi - lo < 0.000001 {
    let flat_h = if hi.abs() < 0.000001 { 4.0 } else { max_h * 0.55 }
    for _ in 0..<n {
      out.push(flat_h)
    }
  } else {
    let span = hi - lo
    for v in values {
      let t = @sf.dclamp((v - lo) / span, 0.0, 1.0)
      out.push(@sf.dmax(4.0, max_h * (0.20 + 0.80 * t)))
    }
  }
  out
}

///|
fn viz_spark_ctx(c : @ui.Ctx, key_prefix : String, values : Array[Double], color : String, w : Double, h : Double) -> Unit {
  ignore(key_prefix)
  let w_safe = if w > 8.0 { w } else { 72.0 }
  let h_safe = if h > 8.0 { h } else { 22.0 }
  let bars = viz_spark_bars(values, h_safe)
  let n = bars.length()
  c.box(
    style=@ui.style(row=true, w=viz_fixed_len(w_safe), h=viz_fixed_len(h_safe), align=AEnd, gap=S0_5),
    fn() {
      for i = 0; i < n; i = i + 1 {
        let bh = bars[i]
        let is_last = i == n - 1
        let col = viz_tone_color(color, 0)
        let bar_bg = if is_last { col } else { @sf.alpha(col, 0.48) }
        c.box(
          style=@ui.style(w=@sf.grow, h=viz_fixed_len(bh), radius=Sm, bg=Data(bar_bg)),
          fn() {  },
        )
        |> ignore
      }
    },
  )
  |> ignore
}

///|
fn viz_spark_node(parent : @view.View, key_prefix : String, values : () -> Array[Double], color : String, w : Double, h : Double, in_row? : Bool = false) -> Unit {
  ignore(key_prefix)
  let w_safe = if w > 8.0 { w } else { 72.0 }
  let h_safe = if h > 8.0 { h } else { 22.0 }
  let vals = values()
  let bars = viz_spark_bars(vals, h_safe)
  let n = bars.length()
  parent.box(fn(row) {
    @sf.style_node(
      row,
      fn() { @ui.style(row=true, w=viz_fixed_len(w_safe), h=viz_fixed_len(h_safe), align=AEnd, gap=S0_5) },
      in_row~,
    )
    for i = 0; i < n; i = i + 1 {
      let bh = bars[i]
      let is_last = i == n - 1
      row.box(fn(bar) {
        @sf.style_node(
          bar,
          fn() {
            let col = viz_tone_color(color, 0)
            let bar_bg = if is_last { col } else { @sf.alpha(col, 0.48) }
            @ui.style(w=@sf.grow, h=viz_fixed_len(bh), radius=Sm, bg=Data(bar_bg))
          },
          in_row=true,
        )
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn viz_chart_bounds(chart : VizChart, kind : String) -> (Double, Double, Int) {
  let mut lo = match chart.min {
    Some(m) => m
    None => 0.0
  }
  let mut hi = match chart.max {
    Some(m) => m
    None => 0.0
  }
  let mut has_val = false
  let mut max_len = chart.labels.length()
  for s in chart.series {
    if s.values.length() > max_len {
      max_len = s.values.length()
    }
  }
  if chart.stacked && (kind == "bar" || kind == "column") {
    for i = 0; i < max_len; i = i + 1 {
      let mut sum = 0.0
      for s in chart.series {
        if i < s.values.length() {
          sum = sum + @sf.dmax(0.0, s.values[i])
        }
      }
      if !has_val || sum > hi {
        hi = sum
        has_val = true
      }
    }
  } else {
    for s in chart.series {
      for v in s.values {
        if !has_val {
          if chart.min is None && v < lo {
            lo = v
          }
          if chart.max is None && v > hi {
            hi = v
          }
          has_val = true
        } else {
          if chart.min is None && v < lo {
            lo = v
          }
          if chart.max is None && v > hi {
            hi = v
          }
        }
      }
    }
  }
  match chart.reference {
    Some(rv) => {
      if chart.min is None && rv < lo {
        lo = rv
      }
      if chart.max is None && rv > hi {
        hi = rv
      }
    }
    None => ()
  }
  if hi <= lo {
    hi = lo + 1.0
  } else if chart.max is None {
    hi = lo + (hi - lo) * 1.08
  }
  let n_cats = if max_len > 1 { max_len } else { 1 }
  (lo, hi, n_cats)
}

///|
fn viz_cartesian_ctx(c : @ui.Ctx, chart : VizChart, kind : String) -> Unit {
  let (lo, hi, n_cats) = viz_chart_bounds(chart, kind)
  let span = @sf.dmax(0.000001, hi - lo)
  let plot_h = if chart.height > 72.0 { chart.height - 32.0 } else { 132.0 }
  let bar_max_h = @sf.dmax(32.0, plot_h - 24.0)
  let s_count = chart.series.length()
  let show_vals = n_cats * (if s_count > 1 { s_count } else { 1 }) <= 10
  let bar_w_len = if s_count > 1 { viz_bar_col_w } else { viz_bar_single_w }
  c.box(style=viz_col_s1, fn() {
    c.box(style=viz_plot_row.then(@ui.style(h=viz_fixed_len(plot_h))), fn() {
      for i = 0; i < n_cats; i = i + 1 {
        c.box(style=viz_cat_col, fn() {
          if chart.stacked && s_count > 1 {
            let mut sum = 0.0
            for s in chart.series {
              if i < s.values.length() {
                sum = sum + @sf.dmax(0.0, s.values[i])
              }
            }
            if show_vals && sum > 0.0 {
              c.text(viz_fmt_num(sum, ""), style=@sf.caption) |> ignore
            }
            let total_h = @sf.dmax(4.0, bar_max_h * @sf.dclamp((sum - lo) / span, 0.0, 1.0))
            c.box(
              style=@ui.style(w=viz_bar_single_w, h=viz_fixed_len(total_h), radius=Sm, clip=true),
              fn() {
                for s_idx = s_count - 1; s_idx >= 0; s_idx = s_idx - 1 {
                  let s = chart.series[s_idx]
                  let v = if i < s.values.length() { @sf.dmax(0.0, s.values[i]) } else { 0.0 }
                  if v > 0.0 && sum > 0.0 {
                    let seg_h = @sf.dmax(2.0, total_h * (v / sum))
                    let col = viz_tone_color(s.color, s_idx)
                    c.box(
                      style=@ui.style(w=Full, h=viz_fixed_len(seg_h), bg=Data(col)),
                      fn() {  },
                    )
                    |> ignore
                  }
                }
              },
            )
            |> ignore
          } else {
            c.box(style=viz_bar_group_row, fn() {
              for s_idx = 0; s_idx < s_count; s_idx = s_idx + 1 {
                let s = chart.series[s_idx]
                if i < s.values.length() {
                  let v = s.values[i]
                  let bh = @sf.dmax(4.0, bar_max_h * @sf.dclamp((v - lo) / span, 0.0, 1.0))
                  let col = viz_tone_color(s.color, s_idx)
                  let bar_bg = if kind == "area" || kind == "line" { @sf.alpha(col, 0.72) } else { col }
                  c.box(style=viz_bar_item_col, fn() {
                    if show_vals {
                      c.text(viz_fmt_num(v, ""), style=@sf.caption) |> ignore
                    }
                    c.box(
                      style=@ui.style(w=bar_w_len, h=viz_fixed_len(bh), radius=Sm, bg=Data(bar_bg)),
                      fn() {  },
                    )
                    |> ignore
                  })
                  |> ignore
                }
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    if chart.show_grid {
      c.box(style=@ui.style(w=Full, h=viz_line_Line_h, bg=Line), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
fn viz_cartesian_node(parent : @view.View, chart : VizChart, kind : String) -> Unit {
  let (lo, hi, n_cats) = viz_chart_bounds(chart, kind)
  let span = @sf.dmax(0.000001, hi - lo)
  let plot_h = if chart.height > 72.0 { chart.height - 32.0 } else { 132.0 }
  let bar_max_h = @sf.dmax(32.0, plot_h - 24.0)
  let s_count = chart.series.length()
  let show_vals = n_cats * (if s_count > 1 { s_count } else { 1 }) <= 10
  let bar_w_len = if s_count > 1 { viz_bar_col_w } else { viz_bar_single_w }
  parent.box(fn(wrap) {
    @sf.style_node(wrap, fn() { viz_col_s1 })
    wrap.box(fn(plot) {
      @sf.style_node(plot, fn() { viz_plot_row.then(@ui.style(h=viz_fixed_len(plot_h))) })
      for i = 0; i < n_cats; i = i + 1 {
        let cat_idx = i
        plot.box(fn(cat) {
          @sf.style_node(cat, fn() { viz_cat_col }, in_row=true)
          if chart.stacked && s_count > 1 {
            let mut sum = 0.0
            for s in chart.series {
              if cat_idx < s.values.length() {
                sum = sum + @sf.dmax(0.0, s.values[cat_idx])
              }
            }
            if show_vals && sum > 0.0 {
              let sum_txt = viz_fmt_num(sum, "")
              cat.box(fn(w) { @sf.words_node(w, fn() { sum_txt }, fn() { @sf.caption }) |> ignore }) |> ignore
            }
            let total_h = @sf.dmax(4.0, bar_max_h * @sf.dclamp((sum - lo) / span, 0.0, 1.0))
            cat.box(fn(stack) {
              @sf.style_node(stack, fn() { @ui.style(w=viz_bar_single_w, h=viz_fixed_len(total_h), radius=Sm, clip=true) })
              for s_idx = s_count - 1; s_idx >= 0; s_idx = s_idx - 1 {
                let s = chart.series[s_idx]
                let v = if cat_idx < s.values.length() { @sf.dmax(0.0, s.values[cat_idx]) } else { 0.0 }
                if v > 0.0 && sum > 0.0 {
                  let seg_h = @sf.dmax(2.0, total_h * (v / sum))
                  let s_i = s_idx
                  let s_col = s.color
                  stack.box(fn(seg) {
                    @sf.style_node(seg, fn() { @ui.style(w=Full, h=viz_fixed_len(seg_h), bg=Data(viz_tone_color(s_col, s_i))) })
                  })
                  |> ignore
                }
              }
            })
            |> ignore
          } else {
            cat.box(fn(grp) {
              @sf.style_node(grp, fn() { viz_bar_group_row })
              for s_idx = 0; s_idx < s_count; s_idx = s_idx + 1 {
                let s = chart.series[s_idx]
                if cat_idx < s.values.length() {
                  let v = s.values[cat_idx]
                  let bh = @sf.dmax(4.0, bar_max_h * @sf.dclamp((v - lo) / span, 0.0, 1.0))
                  let s_i = s_idx
                  let s_col = s.color
                  let v_txt = viz_fmt_num(v, "")
                  grp.box(fn(item_col) {
                    @sf.style_node(item_col, fn() { viz_bar_item_col }, in_row=true)
                    if show_vals {
                      item_col.box(fn(w) { @sf.words_node(w, fn() { v_txt }, fn() { @sf.caption }) |> ignore }) |> ignore
                    }
                    item_col.box(fn(bar) {
                      @sf.style_node(
                        bar,
                        fn() {
                          let col = viz_tone_color(s_col, s_i)
                          let bar_bg = if kind == "area" || kind == "line" { @sf.alpha(col, 0.72) } else { col }
                          @ui.style(w=bar_w_len, h=viz_fixed_len(bh), radius=Sm, bg=Data(bar_bg))
                        },
                      )
                    })
                    |> ignore
                  })
                  |> ignore
                }
              }
            })
            |> ignore
          }
        })
        |> ignore
      }
    })
    |> ignore
    if chart.show_grid {
      wrap.box(fn(line) {
        @sf.style_node(line, fn() { @ui.style(w=Full, h=viz_line_Line_h, bg=Line) })
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn viz_pie_ctx(c : @ui.Ctx, chart : VizChart) -> Unit {
  let mut total = 0.0
  for s in chart.slices {
    if s.value > 0.0 {
      total = total + s.value
    }
  }
  let denom = if total <= 0.0 { 1.0 } else { total }
  c.box(
    style=@ui.style(row=true, w=Full, h=viz_pie_track_h, radius=Full, clip=true, bg=Data(@sf.theme().p.card2)),
    fn() {
      for idx = 0; idx < chart.slices.length(); idx = idx + 1 {
        let s = chart.slices[idx]
        if s.value > 0.0 {
          let share = @sf.dmax(0.02, s.value / denom)
          let col = viz_tone_color(s.color, idx)
          c.box(
            style=@ui.style(w=Grow(share), h=Full, bg=Data(col)),
            fn() {  },
          )
          |> ignore
        }
      }
    },
  )
  |> ignore
}

///|
fn viz_pie_node(parent : @view.View, chart : VizChart) -> Unit {
  let mut total = 0.0
  for s in chart.slices {
    if s.value > 0.0 {
      total = total + s.value
    }
  }
  let denom = if total <= 0.0 { 1.0 } else { total }
  parent.box(fn(track) {
    @sf.style_node(track, fn() { @ui.style(row=true, w=Full, h=viz_pie_track_h, radius=Full, clip=true, bg=Data(@sf.theme().p.card2)) })
    for idx = 0; idx < chart.slices.length(); idx = idx + 1 {
      let s = chart.slices[idx]
      if s.value > 0.0 {
        let share = @sf.dmax(0.02, s.value / denom)
        let s_i = idx
        let s_col = s.color
        track.box(fn(seg) {
          @sf.style_node(
            seg,
            fn() { @ui.style(w=Grow(share), h=Full, bg=Data(viz_tone_color(s_col, s_i))) },
            in_row=true,
          )
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
fn viz_chart_ctx(c : @ui.Ctx, key_prefix : String, chart : VizChart) -> Unit {
  let kind = @sf.lower(chart.kind)
  let sub = if chart.subtitle != "" && chart.reference_label != "" {
    chart.subtitle + " · " + chart.reference_label
  } else if chart.subtitle != "" {
    chart.subtitle
  } else {
    chart.reference_label
  }
  c.box(style=viz_col_s2, fn() {
    if chart.title != "" || sub != "" || chart.center != "" {
      c.box(style=viz_col_s0_5, fn() {
        if chart.title != "" || chart.center != "" {
          c.box(style=viz_row_between_s2, fn() {
            if chart.title != "" {
              c.text(chart.title, style=@sf.card_title) |> ignore
            }
            if chart.center != "" {
              c.text(chart.center, style=@sf.code) |> ignore
            }
          })
          |> ignore
        }
        if sub != "" {
          c.text(sub, style=@sf.caption) |> ignore
        }
      })
      |> ignore
    }
    if kind == "hbar" {
      viz_hbar_ctx(c, chart)
    } else if kind == "donut" || kind == "pie" {
      viz_pie_ctx(c, chart)
      if chart.show_legend {
        viz_legend_ctx(c, chart, kind)
      }
    } else if kind == "spark" || kind == "sparkline" {
      let vals = if chart.series.length() > 0 { chart.series[0].values } else { [] }
      let color = if chart.series.length() > 0 { chart.series[0].color } else { "" }
      let h = if chart.height > 12.0 { chart.height } else { 28.0 }
      viz_spark_ctx(c, key_prefix, vals, color, 160.0, h)
    } else {
      viz_cartesian_ctx(c, chart, kind)
      if chart.labels.length() > 0 {
        viz_axis_ctx(c, chart)
      }
      if chart.show_legend {
        viz_legend_ctx(c, chart, kind)
      }
    }
  })
  |> ignore
}

///|
fn viz_axis_ctx(c : @ui.Ctx, chart : VizChart) -> Unit {
  let n = chart.labels.length()
  let stride = if n > 8 { (n + 5) / 6 } else { 1 }
  c.box(style=viz_axis_row, fn() {
    for i = 0; i < n; i = i + 1 {
      if i % stride == 0 || i == n - 1 {
        let lbl = chart.labels[i]
        c.box(style=viz_axis_cell, fn() {
          c.text(lbl, style=@sf.caption) |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
fn viz_hbar_ctx(c : @ui.Ctx, chart : VizChart) -> Unit {
  let mut max_v = match chart.max {
    Some(m) => m
    None => 0.0
  }
  for item in chart.items {
    if item.value > max_v {
      max_v = item.value
    }
  }
  if max_v <= 0.0 {
    max_v = 1.0
  }
  c.box(style=viz_col_s2, fn() {
    for idx = 0; idx < chart.items.length(); idx = idx + 1 {
      let item = chart.items[idx]
      let frac = @sf.dclamp(item.value / max_v, 0.0, 1.0)
      let color = viz_tone_color(item.color, idx)
      let val_str = if item.text != "" { item.text } else { viz_fmt_num(item.value, chart.unit) }
      c.box(style=viz_col_s1, fn() {
        c.box(style=viz_row_between_s2, fn() {
          c.text(item.label, style=@sf.body) |> ignore
          c.text(val_str, style=@sf.code) |> ignore
        })
        |> ignore
        @sf.progress(c, "hbar/\{idx}/\{item.label}", Some(frac), w=Fill(1.0), color~)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn viz_legend_ctx(c : @ui.Ctx, chart : VizChart, kind : String) -> Unit {
  if kind == "donut" || kind == "pie" {
    if chart.slices.length() == 0 {
      return
    }
    c.box(style=viz_legend_row, flow=true, fn() {
      for idx = 0; idx < chart.slices.length(); idx = idx + 1 {
        let s = chart.slices[idx]
        let col = viz_tone_color(s.color, idx)
        c.box(style=viz_legend_item, fn() {
          c.box(style=@ui.style(w=viz_legend_dot_side, h=viz_legend_dot_side, radius=Full, bg=Data(col)), fn() {  }) |> ignore
          c.text(s.label + " (" + viz_fmt_num(s.value, chart.unit) + ")", style=@sf.caption) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  } else if chart.series.length() > 1 {
    c.box(style=viz_legend_row, flow=true, fn() {
      for idx = 0; idx < chart.series.length(); idx = idx + 1 {
        let s = chart.series[idx]
        if s.name != "" {
          let col = viz_tone_color(s.color, idx)
          c.box(style=viz_legend_item, fn() {
            c.box(style=@ui.style(w=viz_legend_dot_side, h=viz_legend_dot_side, radius=Full, bg=Data(col)), fn() {  }) |> ignore
            c.text(s.name, style=@sf.caption) |> ignore
          })
          |> ignore
        }
      }
    })
    |> ignore
  }
}

///|
fn viz_chart_node(parent : @view.View, key_prefix : String, chart : VizChart, in_row? : Bool = false) -> Unit {
  let kind = @sf.lower(chart.kind)
  let sub = if chart.subtitle != "" && chart.reference_label != "" {
    chart.subtitle + " · " + chart.reference_label
  } else if chart.subtitle != "" {
    chart.subtitle
  } else {
    chart.reference_label
  }
  parent.box(fn(col) {
    @sf.style_node(col, fn() { viz_col_s2 }, in_row~)
    if chart.title != "" || sub != "" || chart.center != "" {
      col.box(fn(head) {
        @sf.style_node(head, fn() { viz_col_s0_5 })
        if chart.title != "" || chart.center != "" {
          head.box(fn(r) {
            @sf.style_node(r, fn() { viz_row_between_s2 })
            if chart.title != "" {
              let t = chart.title
              r.box(fn(w) {
                @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                @sf.words_node(w, fn() { t }, fn() { @sf.card_title }) |> ignore
              })
              |> ignore
            }
            if chart.center != "" {
              let ctr = chart.center
              r.box(fn(w) {
                @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                @sf.words_node(w, fn() { ctr }, fn() { @sf.code }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
        if sub != "" {
          head.box(fn(w) { @sf.words_node(w, fn() { sub }, fn() { @sf.caption }) |> ignore }) |> ignore
        }
      })
      |> ignore
    }
    if kind == "hbar" {
      viz_hbar_node(col, chart)
    } else if kind == "donut" || kind == "pie" {
      viz_pie_node(col, chart)
      if chart.show_legend {
        viz_legend_node(col, chart, kind)
      }
    } else if kind == "spark" || kind == "sparkline" {
      let vals = if chart.series.length() > 0 { chart.series[0].values } else { [] }
      let color = if chart.series.length() > 0 { chart.series[0].color } else { "" }
      let h = if chart.height > 12.0 { chart.height } else { 28.0 }
      viz_spark_node(col, key_prefix, fn() { vals }, color, 160.0, h)
    } else {
      viz_cartesian_node(col, chart, kind)
      if chart.labels.length() > 0 {
        viz_axis_node(col, chart)
      }
      if chart.show_legend {
        viz_legend_node(col, chart, kind)
      }
    }
  })
  |> ignore
}

///|
fn viz_axis_node(parent : @view.View, chart : VizChart) -> Unit {
  let n = chart.labels.length()
  let stride = if n > 8 { (n + 5) / 6 } else { 1 }
  parent.box(fn(row) {
    @sf.style_node(row, fn() { viz_axis_row })
    for i = 0; i < n; i = i + 1 {
      if i % stride == 0 || i == n - 1 {
        let lbl = chart.labels[i]
        row.box(fn(cell) {
          @sf.style_node(cell, fn() { viz_axis_cell }, in_row=true)
          @sf.words_node(cell, fn() { lbl }, fn() { @sf.caption }) |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
fn viz_hbar_node(parent : @view.View, chart : VizChart) -> Unit {
  let mut max_v = match chart.max {
    Some(m) => m
    None => 0.0
  }
  for item in chart.items {
    if item.value > max_v {
      max_v = item.value
    }
  }
  let denom = if max_v <= 0.0 { 1.0 } else { max_v }
  parent.box(fn(list) {
    @sf.style_node(list, fn() { viz_col_s2 })
    for idx = 0; idx < chart.items.length(); idx = idx + 1 {
      let item = chart.items[idx]
      let i_idx = idx
      let frac = @sf.dclamp(item.value / denom, 0.0, 1.0)
      let val_str = if item.text != "" { item.text } else { viz_fmt_num(item.value, chart.unit) }
      list.box(fn(entry) {
        @sf.style_node(entry, fn() { viz_col_s1 })
        entry.box(fn(r) {
          @sf.style_node(r, fn() { viz_row_between_s2 })
          let lbl = item.label
          r.box(fn(w) {
            @sf.style_node(w, fn() { @ui.style() }, in_row=true)
            @sf.words_node(w, fn() { lbl }, fn() { @sf.body }) |> ignore
          })
          |> ignore
          r.box(fn(w) {
            @sf.style_node(w, fn() { @ui.style() }, in_row=true)
            @sf.words_node(w, fn() { val_str }, fn() { @sf.code }) |> ignore
          })
          |> ignore
        })
        |> ignore
        entry.box(fn(bar) {
          @sf.progress_node(
            bar,
            fn() { Some(frac) },
            fn() { viz_tone_color(item.color, i_idx) },
            fn() { @sf.theme().p.card2 },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
fn viz_legend_node(parent : @view.View, chart : VizChart, kind : String) -> Unit {
  if kind == "donut" || kind == "pie" {
    if chart.slices.length() == 0 {
      return
    }
    parent.box(fn(row) {
      @sf.style_node(row, fn() { viz_legend_row })
      row.wraps(Is(Some(0.0))) |> ignore
      for idx = 0; idx < chart.slices.length(); idx = idx + 1 {
        let s = chart.slices[idx]
        let i_idx = idx
        let txt = s.label + " (" + viz_fmt_num(s.value, chart.unit) + ")"
        row.box(fn(item) {
          @sf.style_node(item, fn() { viz_legend_item }, in_row=true)
          item.box(fn(dot) {
            @sf.style_node(dot, fn() { @ui.style(w=viz_legend_dot_side, h=viz_legend_dot_side, radius=Full, bg=Data(viz_tone_color(s.color, i_idx))) }, in_row=true)
          })
          |> ignore
          item.box(fn(w) {
            @sf.style_node(w, fn() { @ui.style() }, in_row=true)
            @sf.words_node(w, fn() { txt }, fn() { @sf.caption }) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  } else if chart.series.length() > 1 {
    parent.box(fn(row) {
      @sf.style_node(row, fn() { viz_legend_row })
      row.wraps(Is(Some(0.0))) |> ignore
      for idx = 0; idx < chart.series.length(); idx = idx + 1 {
        let s = chart.series[idx]
        if s.name != "" {
          let i_idx = idx
          let name = s.name
          row.box(fn(item) {
            @sf.style_node(item, fn() { viz_legend_item }, in_row=true)
            item.box(fn(dot) {
              @sf.style_node(dot, fn() { @ui.style(w=viz_legend_dot_side, h=viz_legend_dot_side, radius=Full, bg=Data(viz_tone_color(s.color, i_idx))) }, in_row=true)
            })
            |> ignore
            item.box(fn(w) {
              @sf.style_node(w, fn() { @ui.style() }, in_row=true)
              @sf.words_node(w, fn() { name }, fn() { @sf.caption }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      }
    })
    |> ignore
  }
}
