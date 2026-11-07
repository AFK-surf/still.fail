use resvg::{tiny_skia, usvg};
use std::sync::Arc;

// Private host ABI: pointers belong to this module and must be released exactly
// once with the matching function. Inputs remain owned by the caller.
#[unsafe(no_mangle)]
pub extern "C" fn mbsvg_buffer_new(n: usize) -> *mut u8 {
    Box::into_raw(vec![0u8; n].into_boxed_slice()) as *mut u8
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_buffer_free(p: *mut u8, n: usize) {
    unsafe {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, n)));
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbsvg_fonts_new() -> *mut usvg::fontdb::Database {
    Box::into_raw(Box::new(usvg::fontdb::Database::new()))
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_fonts_add(db: *mut usvg::fontdb::Database, p: *const u8, n: usize) {
    unsafe {
        (*db).load_font_data(std::slice::from_raw_parts(p, n).to_vec());
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_fonts_free(db: *mut usvg::fontdb::Database) {
    unsafe {
        drop(Box::from_raw(db));
    }
}

pub fn render(data: &[u8], long_side: u32, db: &usvg::fontdb::Database) -> Option<Vec<u8>> {
    render_with_mapping(data, long_side, db, false)
}

pub fn render_with_mapping(
    data: &[u8],
    long_side: u32,
    db: &usvg::fontdb::Database,
    app: bool,
) -> Option<Vec<u8>> {
    if long_side == 0 {
        return None;
    }
    let mut fonts = db.clone();
    let own = fonts
        .faces()
        .next()
        .and_then(|f| f.families.first())
        .map(|f| f.0.clone())
        .unwrap_or_default();
    fonts.set_serif_family(&own);
    fonts.set_sans_serif_family(&own);
    fonts.set_cursive_family(&own);
    fonts.set_fantasy_family(&own);
    let mono = if app {
        fonts
            .faces()
            .nth(1)
            .and_then(|f| f.families.first())
            .map(|f| f.0.clone())
            .unwrap_or_default()
    } else {
        "JetBrains Mono".into()
    };
    fonts.set_monospace_family(mono);
    let options = usvg::Options {
        fontdb: Arc::new(fonts),
        font_family: own,
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_string: Box::new(|_, _| None),
            ..Default::default()
        },
        ..Default::default()
    };
    let tree = usvg::Tree::from_data(data, &options).ok()?;
    let (w, h) = (tree.size().width(), tree.size().height());
    let width = if w >= h {
        long_side
    } else {
        (long_side as f32 * w / h).round().max(1.0) as u32
    };
    let size = tree.size().to_int_size().scale_to_width(width)?;
    let mut pixmap = tiny_skia::Pixmap::new(size.width(), size.height())?;
    resvg::render(
        &tree,
        tiny_skia::Transform::from_scale(size.width() as f32 / w, size.height() as f32 / h),
        &mut pixmap.as_mut(),
    );
    let mut result = Vec::with_capacity(8 + pixmap.data().len());
    result.extend(size.width().to_le_bytes());
    result.extend(size.height().to_le_bytes());
    for pixel in pixmap.data().chunks_exact(4) {
        let a = pixel[3] as u32;
        for c in &pixel[..3] {
            result.push(if a == 0 {
                0
            } else {
                ((*c as u32 * 255 + a / 2) / a).min(255) as u8
            });
        }
        result.push(pixel[3]);
    }
    Some(result)
}

// Output is width:u32, height:u32, straight RGBA bytes. Header defines its allocation length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_rasterize(
    db: *const usvg::fontdb::Database,
    p: *const u8,
    n: usize,
    side: u32,
) -> *mut u8 {
    unsafe {
        match render(std::slice::from_raw_parts(p, n), side, &*db) {
            Some(v) => Box::into_raw(v.into_boxed_slice()) as *mut u8,
            None => std::ptr::null_mut(),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_rasterize_app(
    db: *const usvg::fontdb::Database,
    p: *const u8,
    n: usize,
    side: u32,
) -> *mut u8 {
    unsafe {
        match render_with_mapping(std::slice::from_raw_parts(p, n), side, &*db, true) {
            Some(v) => Box::into_raw(v.into_boxed_slice()) as *mut u8,
            None => std::ptr::null_mut(),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_buffer_write(p: *mut u8, i: usize, value: u32) {
    unsafe {
        *p.add(i) = value as u8;
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_buffer_read(p: *const u8, i: usize) -> u32 {
    unsafe { *p.add(i) as u32 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbsvg_raster_length(p: *const u8) -> usize {
    unsafe {
        let b = std::slice::from_raw_parts(p, 8);
        8 + 4
            * u32::from_le_bytes(b[0..4].try_into().unwrap()) as usize
            * u32::from_le_bytes(b[4..8].try_into().unwrap()) as usize
    }
}
