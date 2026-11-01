// usvg's filters (tree/filter.rs, parser/filter.rs): `filter` elements and CSS filter functions as primitives.

///|
priv struct Filter {
  id : String
  rect : @skia.NonZeroRect
  primitives : Array[Primitive]
}

///|
priv enum ColorInterp {
  SRGB
  LinearRGB
} derive(Eq)

///|
priv struct Primitive {
  rect : @skia.NonZeroRect
  color_interpolation : ColorInterp
  result : String
  kind : FeKind
}

///|
priv enum FeInput {
  SourceGraphic
  SourceAlpha
  Reference(String)
} derive(Eq)

///|
priv enum ColorMatrixKind {
  CmMatrix(Array[Float])
  CmSaturate(Float)
  CmHueRotate(Float)
  CmLuminanceToAlpha
}

///|
priv enum TransferFn {
  TfIdentity
  TfTable(Array[Float])
  TfDiscrete(Array[Float])
  TfLinear(Float, Float)
  TfGamma(Float, Float, Float)
}

///|
priv enum CompositeOp {
  COver
  CIn
  COut
  CAtop
  CXor
  CLighter
  CArithmetic(Float, Float, Float, Float)
}

///|
priv enum EdgeMode {
  EdgeNone
  EdgeDuplicate
  EdgeWrap
} derive(Eq)

///|
priv enum ColorChannel {
  ChR
  ChG
  ChB
  ChA
}

///|
priv enum LightSource {
  DistantLight(Float, Float)
  /// x, y, z
  PointLight(Float, Float, Float)
  /// x, y, z, points at x, y, z, specular exponent, limiting cone angle
  SpotLight(Float, Float, Float, Float, Float, Float, Float, Float?)
}

///|
priv enum FeKind {
  FeBlend(FeInput, FeInput, @skia.BlendMode)
  FeColorMatrix(FeInput, ColorMatrixKind)
  FeComponentTransfer(FeInput, TransferFn, TransferFn, TransferFn, TransferFn)
  FeComposite(FeInput, FeInput, CompositeOp)
  /// input, target x, target y, columns, rows, matrix, divisor, bias, edge mode, preserve alpha
  FeConvolveMatrix(FeInput, Int, Int, Int, Int, Array[Float], Float, Float, EdgeMode, Bool)
  /// input, surface scale, diffuse constant, lighting colour, light
  FeDiffuseLighting(FeInput, Float, Float, Rgb, LightSource)
  FeDisplacementMap(FeInput, FeInput, Float, ColorChannel, ColorChannel)
  /// input, dx, dy, std dev x, y, colour, opacity
  FeDropShadow(FeInput, Float, Float, Float, Float, Rgb, Float)
  FeFlood(Rgb, Float)
  FeGaussianBlur(FeInput, Float, Float)
  FeImage(Group)
  FeMerge(Array[FeInput])
  /// input, dilate, radius x, y
  FeMorphology(FeInput, Bool, Float, Float)
  FeOffset(FeInput, Float, Float)
  /// input, surface scale, specular constant, specular exponent, lighting colour, light
  FeSpecularLighting(FeInput, Float, Float, Float, Rgb, LightSource)
  FeTile(FeInput)
  /// base frequency x, y, octaves, seed, stitch, fractal noise
  FeTurbulence(Float, Float, Int, Int, Bool, Bool)
}

///|
fn convert_filters(doc : SDoc, node : Int, state : State, object_bbox : @skia.NonZeroRect?, cache : Cache) -> Array[Filter]? {
  let value = match doc.attr(node, "filter") {
    Some(v) => v
    None => return Some([])
  }
  let mut has_invalid_urls = false
  let filters : Array[Filter] = []
  let create = fn(kind : FeKind) {
    let base = match kind {
      FeDropShadow(..) | FeGaussianBlur(..) => @skia.NonZeroRect::from_xywh(-0.5, -0.5, 2.0, 2.0).unwrap()
      _ => @skia.NonZeroRect::from_xywh(-0.1, -0.1, 1.2, 1.2).unwrap()
    }
    match object_bbox {
      Some(b) => {
        let rect = base.bbox_transform(b)
        filters.push({
          id: cache.gen_filter_id(),
          rect,
          primitives: [{ rect, color_interpolation: SRGB, result: "result", kind }],
        })
      }
      None => ()
    }
  }
  for func in parse_filter_values(value) {
    match func {
      None => return Some([])
      Some(FvBlur(std_dev)) => {
        let s = convert_user_length(std_dev, doc, node, "dx", state)
        let s = if s >= 0.0 && ffin(s) { s } else { 0.0 }
        create(FeGaussianBlur(SourceGraphic, s, s))
      }
      Some(FvDropShadow(color, dx, dy, std_dev)) => {
        let s = convert_user_length(std_dev, doc, node, "dx", state)
        let s = if s >= 0.0 && ffin(s) { s } else { 0.0 }
        let c = match color {
          Some(c) => c
          None => doc.find_color(node)
        }
        let (rgb, a) = split_alpha(c)
        create(
          FeDropShadow(
            SourceGraphic,
            convert_user_length(dx, doc, node, "dx", state),
            convert_user_length(dy, doc, node, "dy", state),
            s,
            s,
            rgb,
            a,
          ),
        )
      }
      Some(FvBrightness(amount)) => {
        let a = fd(amount)
        create(FeComponentTransfer(SourceGraphic, TfLinear(a, 0.0), TfLinear(a, 0.0), TfLinear(a, 0.0), TfIdentity))
      }
      Some(FvContrast(amount)) => {
        let a = fd(amount)
        let i = -(0.5 * a) + 0.5
        create(FeComponentTransfer(SourceGraphic, TfLinear(a, i), TfLinear(a, i), TfLinear(a, i), TfIdentity))
      }
      Some(FvGrayscale(amount)) => {
        let a : Float = fd(if amount < 1.0 { amount } else { 1.0 })
        let r : Float = 1.0 - a
        create(
          FeColorMatrix(
            SourceGraphic,
            CmMatrix([
              0.2126 + 0.7874 * r,
              0.7152 - 0.7152 * r,
              0.0722 - 0.0722 * r,
              0.0,
              0.0,
              0.2126 - 0.2126 * r,
              0.7152 + 0.2848 * r,
              0.0722 - 0.0722 * r,
              0.0,
              0.0,
              0.2126 - 0.2126 * r,
              0.7152 - 0.7152 * r,
              0.0722 + 0.9278 * r,
              0.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
            ]),
          ),
        )
      }
      Some(FvSepia(amount)) => {
        let a : Float = fd(if amount < 1.0 { amount } else { 1.0 })
        let r : Float = 1.0 - a
        create(
          FeColorMatrix(
            SourceGraphic,
            CmMatrix([
              0.393 + 0.607 * r,
              0.769 - 0.769 * r,
              0.189 - 0.189 * r,
              0.0,
              0.0,
              0.349 - 0.349 * r,
              0.686 + 0.314 * r,
              0.168 - 0.168 * r,
              0.0,
              0.0,
              0.272 - 0.272 * r,
              0.534 - 0.534 * r,
              0.131 + 0.869 * r,
              0.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
            ]),
          ),
        )
      }
      Some(FvSaturate(amount)) => {
        let a = fd(amount)
        create(FeColorMatrix(SourceGraphic, CmSaturate(if a >= 0.0 && ffin(a) { a } else { 0.0 })))
      }
      Some(FvHueRotate(deg)) => create(FeColorMatrix(SourceGraphic, CmHueRotate(fd(deg))))
      Some(FvInvert(amount)) => {
        let a : Float = fd(if amount < 1.0 { amount } else { 1.0 })
        create(FeComponentTransfer(SourceGraphic, TfTable([a, 1.0 - a]), TfTable([a, 1.0 - a]), TfTable([a, 1.0 - a]), TfIdentity))
      }
      Some(FvOpacity(amount)) => {
        let a : Float = fd(if amount < 1.0 { amount } else { 1.0 })
        create(FeComponentTransfer(SourceGraphic, TfIdentity, TfIdentity, TfIdentity, TfTable([0.0, a])))
      }
      Some(FvUrl(url)) => {
        let link = doc.element_by_id(url)
        if link >= 0 {
          match convert_filter_url(doc, link, state, object_bbox, cache) {
            Ok(Some(f)) => filters.push(f)
            Ok(None) => ()
            Err(_) => has_invalid_urls = true
          }
        } else {
          has_invalid_urls = true
        }
      }
    }
  }
  if filters.is_empty() && has_invalid_urls {
    return None
  }
  Some(filters)
}

///|
fn convert_filter_url(
  doc : SDoc,
  node : Int,
  state : State,
  object_bbox : @skia.NonZeroRect?,
  cache : Cache,
) -> Result[Filter?, Unit] {
  let units = convert_units(doc, node, "filterUnits", ObjectBoundingBox)
  let primitive_units = convert_units(doc, node, "primitiveUnits", UserSpaceOnUse)
  let cacheable = units == UserSpaceOnUse && primitive_units == UserSpaceOnUse
  if cacheable {
    match cache.filters.get(doc.element_id(node)) {
      Some(f) => return Ok(Some(f))
      None => ()
    }
  }
  let mut rect = match
    @skia.NonZeroRect::from_xywh(
      resolve_number(doc, node, "x", units, state, { number: -10.0, unit: Percent }),
      resolve_number(doc, node, "y", units, state, { number: -10.0, unit: Percent }),
      resolve_number(doc, node, "width", units, state, { number: 120.0, unit: Percent }),
      resolve_number(doc, node, "height", units, state, { number: 120.0, unit: Percent }),
    ) {
    Some(r) => r
    None => return Err(())
  }
  if units == ObjectBoundingBox {
    match object_bbox {
      Some(b) => rect = rect.bbox_transform(b)
      None => return Err(())
    }
  }
  let with_primitives = match find_filter_with_primitives(doc, node) {
    Some(n) => n
    None => return Err(())
  }
  let primitives = collect_primitives(doc, with_primitives, primitive_units, state, object_bbox, rect, cache)
  if primitives.is_empty() {
    return Err(())
  }
  let mut id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return Err(())
  }
  if !cacheable && cache.filters.contains(id) {
    id = cache.gen_filter_id()
  }
  let f : Filter = { id, rect, primitives }
  cache.filters[id] = f
  Ok(Some(f))
}

///|
fn find_filter_with_primitives(doc : SDoc, node : Int) -> Int? {
  for link in doc.href_chain(node) {
    if doc.tag(link) != "filter" {
      return None
    }
    if doc.has_children(link) {
      return Some(link)
    }
  }
  None
}

///|
fn collect_primitives(
  doc : SDoc,
  filter : Int,
  units : Units,
  state : State,
  object_bbox : @skia.NonZeroRect?,
  region : @skia.NonZeroRect,
  cache : Cache,
) -> Array[Primitive] {
  let primitives : Array[Primitive] = []
  let names : Set[String] = Set::new()
  let mut idx = 1
  let (scale_w, scale_h) : (Float, Float) = if units == ObjectBoundingBox {
    match object_bbox {
      Some(b) => (b.width(), b.height())
      None => return []
    }
  } else {
    (1.0, 1.0)
  }
  for child in doc.children(filter) {
    if !doc.is_element(child) {
      continue
    }
    let tag = doc.tag(child)
    let sub = match resolve_primitive_region(doc, child, units, state, object_bbox, region) {
      Some(r) => r
      None => break
    }
    let kind = match tag {
      "feDropShadow" => convert_fe_drop_shadow(doc, child, scale_w, scale_h, primitives)
      "feGaussianBlur" => {
        let (sx, sy) = convert_std_dev_attr(doc, child, scale_w, scale_h, "0 0")
        FeGaussianBlur(resolve_input(doc, child, "in", primitives), sx, sy)
      }
      "feOffset" =>
        FeOffset(
          resolve_input(doc, child, "in", primitives),
          doc.attr_number(child, "dx").unwrap_or(0.0) * scale_w,
          doc.attr_number(child, "dy").unwrap_or(0.0) * scale_h,
        )
      "feBlend" => {
        let mode = match doc.attr(child, "mode") {
          Some(v) => parse_blend_mode("mode", v).unwrap_or(SourceOver)
          None => SourceOver
        }
        let i1 = resolve_input(doc, child, "in", primitives)
        let i2 = resolve_input(doc, child, "in2", primitives)
        FeBlend(i1, i2, mode)
      }
      "feFlood" => {
        let (c, a) = split_alpha(doc.attr_color(child, "flood-color").unwrap_or(SColor::black()))
        FeFlood(c, opacity_clamped(a * doc.attr_opacity(child, "flood-opacity").unwrap_or(1.0)))
      }
      "feComposite" => convert_fe_composite(doc, child, primitives)
      "feMerge" => {
        let inputs = []
        for c in doc.children(child) {
          inputs.push(resolve_input(doc, c, "in", primitives))
        }
        FeMerge(inputs)
      }
      "feTile" => FeTile(resolve_input(doc, child, "in", primitives))
      "feImage" => convert_fe_image(doc, child, sub, state, cache)
      "feComponentTransfer" => convert_fe_component_transfer(doc, child, primitives)
      "feColorMatrix" => FeColorMatrix(resolve_input(doc, child, "in", primitives), convert_color_matrix_kind(doc, child))
      "feConvolveMatrix" => convert_fe_convolve_matrix(doc, child, primitives).unwrap_or(dummy_primitive())
      "feMorphology" => convert_fe_morphology(doc, child, scale_w, scale_h, primitives)
      "feDisplacementMap" => {
        let channel = fn(aid) -> ColorChannel {
          match doc.attr(child, aid) {
            Some("R") => ChR
            Some("G") => ChG
            Some("B") => ChB
            _ => ChA
          }
        }
        let scale = (scale_w + scale_h) / 2.0
        FeDisplacementMap(
          resolve_input(doc, child, "in", primitives),
          resolve_input(doc, child, "in2", primitives),
          doc.attr_number(child, "scale").unwrap_or(0.0) * scale,
          channel("xChannelSelector"),
          channel("yChannelSelector"),
        )
      }
      "feTurbulence" => convert_fe_turbulence(doc, child)
      "feDiffuseLighting" =>
        match convert_light_source(doc, child) {
          Some(light) =>
            FeDiffuseLighting(
              resolve_input(doc, child, "in", primitives),
              doc.attr_number(child, "surfaceScale").unwrap_or(1.0),
              doc.attr_number(child, "diffuseConstant").unwrap_or(1.0),
              convert_lighting_color(doc, child),
              light,
            )
          None => dummy_primitive()
        }
      "feSpecularLighting" =>
        match convert_light_source(doc, child) {
          Some(light) => {
            let e = doc.attr_number(child, "specularExponent").unwrap_or(1.0)
            if !(e >= 1.0 && e <= 128.0) {
              dummy_primitive()
            } else {
              FeSpecularLighting(
                resolve_input(doc, child, "in", primitives),
                doc.attr_number(child, "surfaceScale").unwrap_or(1.0),
                doc.attr_number(child, "specularConstant").unwrap_or(1.0),
                e,
                convert_lighting_color(doc, child),
                light,
              )
            }
          }
          None => dummy_primitive()
        }
      _ => continue
    }
    let ci = match doc.find_attr(child, "color-interpolation-filters") {
      Some("sRGB") => SRGB
      _ => LinearRGB
    }
    let result = match doc.attr(child, "result") {
      Some(s) => {
        names.add(s)
        idx += 1
        s
      }
      None => {
        let mut name = ""
        while true {
          name = "result" + idx.to_string()
          idx += 1
          if !names.contains(name) {
            break
          }
        }
        name
      }
    }
    primitives.push({ rect: sub, color_interpolation: ci, result, kind })
  }
  primitives
}

///|
fn resolve_primitive_region(
  doc : SDoc,
  fe : Int,
  units : Units,
  state : State,
  bbox : @skia.NonZeroRect?,
  region : @skia.NonZeroRect,
) -> @skia.NonZeroRect? {
  let mut x = doc.try_convert_length(fe, "x", units, state)
  let mut y = doc.try_convert_length(fe, "y", units, state)
  let mut w = doc.try_convert_length(fe, "width", units, state)
  let mut h = doc.try_convert_length(fe, "height", units, state)
  if units == ObjectBoundingBox {
    let b = match bbox {
      Some(b) => b
      None => return None
    }
    x = x.map(fn(v) { b.x() + v * b.width() })
    y = y.map(fn(v) { b.y() + v * b.height() })
    w = w.map(fn(v) { v * b.width() })
    h = h.map(fn(v) { v * b.height() })
  }
  @skia.NonZeroRect::from_xywh(
    x.unwrap_or(region.x()),
    y.unwrap_or(region.y()),
    w.unwrap_or(region.width()),
    h.unwrap_or(region.height()),
  )
}

///|
fn dummy_primitive() -> FeKind {
  FeFlood(rgb_black, 0.0)
}

///|
fn resolve_input(doc : SDoc, node : Int, aid : String, primitives : Array[Primitive]) -> FeInput {
  match doc.attr(node, aid) {
    Some(s) => {
      let input = match s {
        "SourceGraphic" => SourceGraphic
        "SourceAlpha" => SourceAlpha
        "BackgroundImage" | "BackgroundAlpha" | "FillPaint" | "StrokePaint" => SourceGraphic
        _ => Reference(s)
      }
      match input {
        Reference(name) =>
          if !primitives.iter().any(fn(p) { p.result == name }) {
            if primitives.is_empty() {
              SourceGraphic
            } else {
              Reference(primitives[primitives.length() - 1].result)
            }
          } else {
            input
          }
        _ => input
      }
    }
    None =>
      if primitives.is_empty() {
        SourceGraphic
      } else {
        Reference(primitives[primitives.length() - 1].result)
      }
  }
}

///|
fn convert_color_matrix_kind(doc : SDoc, fe : Int) -> ColorMatrixKind {
  let identity : Array[Float] = [
    1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
  ]
  match doc.attr(fe, "type") {
    Some("saturate") =>
      match doc.attr_numbers(fe, "values") {
        Some(list) =>
          if !list.is_empty() {
            let v = list[0]
            CmSaturate(if v > 1.0 { 1.0 } else if v >= 0.0 { v } else { 0.0 })
          } else {
            CmSaturate(1.0)
          }
        None => CmMatrix(identity)
      }
    Some("hueRotate") =>
      match doc.attr_numbers(fe, "values") {
        Some(list) => CmHueRotate(if list.is_empty() { 0.0 } else { list[0] })
        None => CmMatrix(identity)
      }
    Some("luminanceToAlpha") => CmLuminanceToAlpha
    _ =>
      match doc.attr_numbers(fe, "values") {
        Some(list) => if list.length() == 20 { CmMatrix(list) } else { CmMatrix(identity) }
        None => CmMatrix(identity)
      }
  }
}

///|
fn convert_fe_component_transfer(doc : SDoc, fe : Int, primitives : Array[Primitive]) -> FeKind {
  let input = resolve_input(doc, fe, "in", primitives)
  let mut r = TfIdentity
  let mut g = TfIdentity
  let mut b = TfIdentity
  let mut a = TfIdentity
  for child in doc.children(fe) {
    if !doc.is_element(child) {
      continue
    }
    let func = match doc.attr(child, "type") {
      Some("identity") => Some(TfIdentity)
      Some("table") => Some(TfTable(doc.attr_numbers(child, "tableValues").unwrap_or([])))
      Some("discrete") => Some(TfDiscrete(doc.attr_numbers(child, "tableValues").unwrap_or([])))
      Some("linear") =>
        Some(TfLinear(doc.attr_number(child, "slope").unwrap_or(1.0), doc.attr_number(child, "intercept").unwrap_or(0.0)))
      Some("gamma") =>
        Some(
          TfGamma(
            doc.attr_number(child, "amplitude").unwrap_or(1.0),
            doc.attr_number(child, "exponent").unwrap_or(1.0),
            doc.attr_number(child, "offset").unwrap_or(0.0),
          ),
        )
      _ => None
    }
    match func {
      Some(f) =>
        match doc.tag(child) {
          "feFuncR" => r = f
          "feFuncG" => g = f
          "feFuncB" => b = f
          "feFuncA" => a = f
          _ => ()
        }
      None => ()
    }
  }
  FeComponentTransfer(input, r, g, b, a)
}

///|
fn convert_fe_composite(doc : SDoc, fe : Int, primitives : Array[Primitive]) -> FeKind {
  let op = match doc.attr(fe, "operator").unwrap_or("over") {
    "in" => CIn
    "out" => COut
    "atop" => CAtop
    "xor" => CXor
    "lighter" => CLighter
    "arithmetic" =>
      CArithmetic(
        doc.attr_number(fe, "k1").unwrap_or(0.0),
        doc.attr_number(fe, "k2").unwrap_or(0.0),
        doc.attr_number(fe, "k3").unwrap_or(0.0),
        doc.attr_number(fe, "k4").unwrap_or(0.0),
      )
    _ => COver
  }
  let i1 = resolve_input(doc, fe, "in", primitives)
  let i2 = resolve_input(doc, fe, "in2", primitives)
  FeComposite(i1, i2, op)
}

///|
fn convert_fe_convolve_matrix(doc : SDoc, fe : Int, primitives : Array[Primitive]) -> FeKind? {
  let parse_target = fn(target : Float?, order : Int) -> Int? {
    let def = f2u((fi(order) / 2.0).floor())
    let t = f2i(target.unwrap_or(fi(def)))
    if t < 0 || t >= order {
      None
    } else {
      Some(t)
    }
  }
  let mut order_x = 3
  let mut order_y = 3
  match doc.attr(fe, "order") {
    Some(value) => {
      let list = parse_number_list(value)
      let x = match list.get(0) {
        Some(Some(n)) => d2i_sat(n)
        _ => 3
      }
      let y = match list.get(1) {
        Some(Some(n)) => d2i_sat(n)
        _ => x
      }
      if x > 0 && y > 0 {
        order_x = x
        order_y = y
      }
    }
    None => ()
  }
  let mut matrix : Array[Float] = []
  match doc.attr_numbers(fe, "kernelMatrix") {
    Some(list) => if list.length().to_int64() == order_x.to_int64() * order_y.to_int64() { matrix = list }
    None => ()
  }
  let mut kernel_sum : Float = 0.0
  for v in matrix {
    kernel_sum = kernel_sum + v
  }
  kernel_sum = fround(kernel_sum * 1000000.0) / 1000000.0
  if approx_zero(kernel_sum) {
    kernel_sum = 1.0
  }
  let divisor = doc.attr_number(fe, "divisor").unwrap_or(kernel_sum)
  if approx_zero(divisor) {
    return None
  }
  let bias = doc.attr_number(fe, "bias").unwrap_or(0.0)
  let tx = match parse_target(doc.attr_number(fe, "targetX"), order_x) {
    Some(t) => t
    None => return None
  }
  let ty = match parse_target(doc.attr_number(fe, "targetY"), order_y) {
    Some(t) => t
    None => return None
  }
  if order_x * order_y != matrix.length() || tx >= order_x || ty >= order_y {
    return None
  }
  let edge = match doc.attr(fe, "edgeMode").unwrap_or("duplicate") {
    "none" => EdgeNone
    "wrap" => EdgeWrap
    _ => EdgeDuplicate
  }
  let preserve_alpha = doc.attr(fe, "preserveAlpha").unwrap_or("false") == "true"
  Some(
    FeConvolveMatrix(
      resolve_input(doc, fe, "in", primitives),
      tx,
      ty,
      order_x,
      order_y,
      matrix,
      divisor,
      bias,
      edge,
      preserve_alpha,
    ),
  )
}

///|
/// Rust's `f64 as i32`.
fn d2i_sat(x : Double) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
fn convert_std_dev_attr(doc : SDoc, fe : Int, sw : Float, sh : Float, default : String) -> (Float, Float) {
  let text = doc.attr(fe, "stdDeviation").unwrap_or(default)
  let list = parse_number_list(text)
  let n = fn(i : Int) -> Double? {
    match list.get(i) {
      Some(Some(v)) => Some(v)
      _ => None
    }
  }
  let (x, y) = match (n(0), n(1), n(2)) {
    (Some(a), Some(b), None) => (a, b)
    (Some(a), None, None) => (a, a)
    _ => (0.0, 0.0)
  }
  let x = fd(x) * sw
  let y = fd(y) * sh
  (if x >= 0.0 && ffin(x) { x } else { 0.0 }, if y >= 0.0 && ffin(y) { y } else { 0.0 })
}

///|
fn convert_fe_drop_shadow(doc : SDoc, fe : Int, sw : Float, sh : Float, primitives : Array[Primitive]) -> FeKind {
  let (sx, sy) = convert_std_dev_attr(doc, fe, sw, sh, "2 2")
  let (c, a) = split_alpha(doc.attr_color(fe, "flood-color").unwrap_or(SColor::black()))
  let fo = doc.attr_opacity(fe, "flood-opacity").unwrap_or(1.0)
  FeDropShadow(
    resolve_input(doc, fe, "in", primitives),
    doc.attr_number(fe, "dx").unwrap_or(2.0) * sw,
    doc.attr_number(fe, "dy").unwrap_or(2.0) * sh,
    sx,
    sy,
    c,
    opacity_clamped(a * fo),
  )
}

///|
fn convert_fe_morphology(doc : SDoc, fe : Int, sw : Float, sh : Float, primitives : Array[Primitive]) -> FeKind {
  let dilate = doc.attr(fe, "operator") == Some("dilate")
  let mut rxo = sw
  let mut ryo = sh
  match doc.attr_numbers(fe, "radius") {
    Some(list) => {
      let mut rx : Float = 0.0
      let mut ry : Float = 0.0
      if list.length() == 2 {
        rx = list[0]
        ry = list[1]
      } else if list.length() == 1 {
        rx = list[0]
        ry = list[0]
      }
      if approx_zero(rx) && approx_zero(ry) {
        rx = 1.0
        ry = 1.0
      }
      if approx_zero(rx) && !approx_zero(ry) {
        rx = 1.0
      }
      if !approx_zero(rx) && approx_zero(ry) {
        ry = 1.0
      }
      if !sign_negative(rx) && !sign_negative(ry) {
        rxo = rx * sw
        ryo = ry * sh
      }
    }
    None => ()
  }
  FeMorphology(resolve_input(doc, fe, "in", primitives), dilate, rxo, ryo)
}

///|
fn convert_fe_turbulence(doc : SDoc, fe : Int) -> FeKind {
  let mut fx : Float = 0.0
  let mut fy : Float = 0.0
  match doc.attr_numbers(fe, "baseFrequency") {
    Some(list) => {
      let mut x : Float = 0.0
      let mut y : Float = 0.0
      if list.length() == 2 {
        x = list[0]
        y = list[1]
      } else if list.length() == 1 {
        x = list[0]
        y = list[0]
      }
      if !sign_negative(x) && !sign_negative(y) {
        fx = x
        fy = y
      }
    }
    None => ()
  }
  let mut octaves = doc.attr_number(fe, "numOctaves").unwrap_or(1.0)
  if sign_negative(octaves) {
    octaves = 0.0
  }
  let fractal = doc.attr(fe, "type").unwrap_or("turbulence") == "fractalNoise"
  FeTurbulence(
    fx,
    fy,
    f2u(fround(octaves)),
    f2i(doc.attr_number(fe, "seed").unwrap_or(0.0).trunc()),
    doc.attr(fe, "stitchTiles") == Some("stitch"),
    fractal,
  )
}

///|
fn convert_lighting_color(doc : SDoc, node : Int) -> Rgb {
  match doc.attr(node, "lighting-color") {
    Some("currentColor") => split_alpha(doc.find_color(node)).0
    Some(v) =>
      match parse_color_str(v) {
        Some(c) => split_alpha(c).0
        None => { r: 255, g: 255, b: 255 }
      }
    None => { r: 255, g: 255, b: 255 }
  }
}

///|
fn convert_light_source(doc : SDoc, parent : Int) -> LightSource? {
  let mut child = -1
  for c in doc.children(parent) {
    let t = doc.tag(c)
    if t == "feDistantLight" || t == "fePointLight" || t == "feSpotLight" {
      child = c
      break
    }
  }
  if child < 0 {
    return None
  }
  let n = fn(aid) { doc.attr_number(child, aid).unwrap_or(0.0) }
  match doc.tag(child) {
    "feDistantLight" => Some(DistantLight(n("azimuth"), n("elevation")))
    "fePointLight" => Some(PointLight(n("x"), n("y"), n("z")))
    _ => {
      let e = doc.attr_number(child, "specularExponent").unwrap_or(1.0)
      let e = if e >= 0.0 && ffin(e) { e } else { 1.0 }
      Some(
        SpotLight(
          n("x"),
          n("y"),
          n("z"),
          n("pointsAtX"),
          n("pointsAtY"),
          n("pointsAtZ"),
          e,
          doc.attr_number(child, "limitingConeAngle"),
        ),
      )
    }
  }
}

///|
fn convert_fe_image(doc : SDoc, fe : Int, sub : @skia.NonZeroRect, state : State, cache : Cache) -> FeKind {
  let rendering = match doc.find_attr(fe, "image-rendering") {
    Some(v) => parse_image_rendering(v).unwrap_or(state.opt.image_rendering)
    None => state.opt.image_rendering
  }
  // try_attribute::<SvgNode>(Href): a link to an element of the document
  let link = match doc.raw_attr(fe, "href") {
    Some(v) =>
      match parse_iri_str(v) {
        Some(l) => doc.element_by_id(l)
        None => -1
      }
    None => -1
  }
  if link >= 0 {
    let root = Group::empty()
    convert_element(doc, link, { ..state, fe_image_link: true }, cache, root)
    if root.children.is_empty() {
      return dummy_primitive()
    }
    update_paint_servers(root, @skia.Transform::default(), None, None, cache)
    return FeImage(root)
  }
  let href = match doc.raw_attr(fe, "href") {
    Some(h) => h
    None => return dummy_primitive()
  }
  let data = match get_href_data(href, state) {
    Some(d) => d
    None => return dummy_primitive()
  }
  let actual = match image_actual_size(data) {
    Some(s) => s
    None => return dummy_primitive()
  }
  let aspect = doc.attr_aspect(fe).unwrap_or(AspectRatio::default())
  let root = Group::empty()
  match sub.translate_to(0.0, 0.0) {
    Some(r) => convert_image_inner(data, cache.gen_image_id(), true, rendering, aspect, actual, r, cache, root)
    None => return dummy_primitive()
  }
  FeImage(root)
}
