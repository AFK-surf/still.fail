use std::{cell::RefCell, io::{self, Write}, rc::Rc};

#[derive(Clone)]
struct Sink(Rc<RefCell<Vec<u8>>>);
impl Write for Sink {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> { Ok(()) }
}

pub struct Rows {
    stream: png::StreamWriter<'static, Sink>,
    output: Sink,
    row: Vec<u8>,
    remaining: u32,
}

// Private ABI: new owns a stream; end consumes it, or free cancels it. Row input
// remains borrowed. The returned output belongs to the caller until output_free.
#[unsafe(no_mangle)]
pub extern "C" fn mbpng_new(w: u32, h: u32) -> *mut Rows {
    if w == 0 || h == 0 || w > i32::MAX as u32 / 4 || h > i32::MAX as u32 {
        return std::ptr::null_mut();
    }
    let output = Sink(Rc::new(RefCell::new(Vec::new())));
    let mut encoder = png::Encoder::new(output.clone(), w, h);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.set_compression(png::Compression::Balanced);
    let stream = match encoder.write_header().and_then(|w| w.into_stream_writer()) {
        Ok(stream) => stream,
        Err(_) => return std::ptr::null_mut(),
    };
    Box::into_raw(Box::new(Rows { stream, output, row: vec![0; w as usize * 3], remaining: h }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_add(handle: *mut Rows, ptr: *const u8, len: usize, count: u32) -> bool {
    let Some(rows) = (unsafe { handle.as_mut() }) else { return false; };
    let count = count.min(rows.remaining) as usize;
    if count == 0 { return true; }
    let width = rows.row.len() / 3;
    let Some(needed) = count.checked_mul(width * 4) else { return false; };
    if ptr.is_null() || len < needed { return false; }
    let data = unsafe { std::slice::from_raw_parts(ptr, needed) };
    for input in data.chunks_exact(width * 4) {
        for (rgba, rgb) in input.chunks_exact(4).zip(rows.row.chunks_exact_mut(3)) {
            rgb.copy_from_slice(&rgba[..3]);
        }
        if rows.stream.write_all(&rows.row).is_err() { return false; }
        rows.remaining -= 1;
    }
    true
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_end(handle: *mut Rows) -> *mut Vec<u8> {
    if handle.is_null() { return std::ptr::null_mut(); }
    let Rows { mut stream, output, mut row, remaining } = *unsafe { Box::from_raw(handle) };
    row.fill(0);
    for _ in 0..remaining {
        if stream.write_all(&row).is_err() { return std::ptr::null_mut(); }
    }
    if stream.finish().is_err() { return std::ptr::null_mut(); }
    let bytes = std::mem::take(&mut *output.0.borrow_mut());
    if bytes.len() > i32::MAX as usize { return std::ptr::null_mut(); }
    Box::into_raw(Box::new(bytes))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_free(handle: *mut Rows) {
    if !handle.is_null() { drop(unsafe { Box::from_raw(handle) }); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_output_ptr(bytes: *mut Vec<u8>) -> *mut u8 {
    unsafe { (*bytes).as_mut_ptr() }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_output_len(bytes: *const Vec<u8>) -> usize {
    unsafe { (*bytes).len() }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbpng_output_free(bytes: *mut Vec<u8>) {
    if !bytes.is_null() { drop(unsafe { Box::from_raw(bytes) }); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn short_input_is_rejected_before_mutation_and_missing_rows_are_black() {
        unsafe {
            assert!(mbpng_new(0, 2).is_null());
            assert!(mbpng_new(u32::MAX, 2).is_null());
            let rows = mbpng_new(2, 2);
            let input = [64u8; 8];
            assert!(!mbpng_add(rows, input.as_ptr(), 7, 1));
            assert!(!mbpng_add(rows, std::ptr::null(), 8, 1));
            assert!(mbpng_add(rows, input.as_ptr(), 8, 1));
            let bytes = mbpng_end(rows);
            let decoder = png::Decoder::new(std::io::Cursor::new(&*bytes));
            let mut reader = decoder.read_info().unwrap();
            let mut data = vec![0; reader.output_buffer_size().unwrap()];
            reader.next_frame(&mut data).unwrap();
            assert_eq!(data, [64,64,64,64,64,64,0,0,0,0,0,0]);
            mbpng_output_free(bytes);
            let partial = mbpng_new(2, 100_000);
            assert!(mbpng_add(partial, input.as_ptr(), 8, 1));
            mbpng_free(partial);
            mbpng_free(std::ptr::null_mut());
        }
    }
    #[test]
    fn rows_past_the_height_are_ignored() {
        unsafe {
            let rows = mbpng_new(1, 1);
            let pixel = [20, 30, 40, 0];
            assert!(mbpng_add(rows, pixel.as_ptr(), pixel.len(), u32::MAX));
            assert!(mbpng_add(rows, std::ptr::null(), 0, u32::MAX));
            mbpng_output_free(mbpng_end(rows));
        }
    }
}
