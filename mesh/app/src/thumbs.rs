//! Small copies of the images sent in chats, for the chat to show: a chat of screenshots would otherwise have pages
//! take in megabytes to show each at a few hundred pixels. Made when an image is kept (and on first asking for one kept
//! before), in the station's data directory, by the image's path; the image itself stays as it was, for the preview.

use std::io::Cursor;
use std::path::{Path, PathBuf};

use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{DynamicImage, ImageFormat, ImageReader};
use sha2::{Digest, Sha256};

/// The largest a chat shows an image (its box is at most 360×300), at twice that for sharp screens.
const MAX_W: u32 = 720;
const MAX_H: u32 = 600;
/// An image already this small is shown itself.
const SMALL: u64 = 24 * 1024;

/// Where the thumbnails are kept.
pub fn dir(data_dir: &Path) -> PathBuf {
    data_dir.join("thumbs")
}

/// Whether a file is an image a thumbnail is made for (a GIF would lose its motion).
pub fn wanted(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    [".png", ".jpg", ".jpeg", ".webp"].iter().any(|e| lower.ends_with(e))
}

/// The image's thumbnail and its type, made if it is not there yet; `None` when the image is shown itself (small
/// already, or not readable as an image).
pub fn thumbnail(image: &Path, dir: &Path) -> Option<(PathBuf, &'static str)> {
    let name = image.file_name()?.to_str()?;
    if !wanted(name) {
        return None;
    }
    let meta = std::fs::metadata(image).ok()?;
    if meta.len() <= SMALL {
        return None;
    }
    let id = hex::encode(&Sha256::digest(image.to_string_lossy().as_bytes())[..16]);
    for (ext, kind) in [("jpg", "image/jpeg"), ("png", "image/png")] {
        let path = dir.join(format!("{id}.{ext}"));
        if path.is_file() {
            return Some((path, kind));
        }
    }
    let decoded = ImageReader::open(image).ok()?.with_guessed_format().ok()?.decode().ok()?;
    // Resampled with care: most are screenshots of text, which a quick filter leaves jagged.
    let small = if decoded.width() > MAX_W || decoded.height() > MAX_H { decoded.resize(MAX_W, MAX_H, FilterType::CatmullRom) } else { decoded };
    // Clear parts stay clear (PNG); anything else is a photo or a screenshot, smallest as JPEG.
    let clear = small.color().has_alpha() && small.to_rgba8().pixels().any(|p| p.0[3] < 255);
    let (ext, kind, bytes) = if clear {
        ("png", "image/png", png(&small)?)
    } else {
        ("jpg", "image/jpeg", jpeg(&small)?)
    };
    // No smaller than the image itself: it is shown as it is.
    if bytes.len() as u64 >= meta.len() {
        return None;
    }
    std::fs::create_dir_all(dir).ok()?;
    let path = dir.join(format!("{id}.{ext}"));
    // Written whole before it is there to be read.
    let partial = dir.join(format!("{id}.{ext}.part"));
    std::fs::write(&partial, bytes).ok()?;
    std::fs::rename(&partial, &path).ok()?;
    Some((path, kind))
}

fn png(image: &DynamicImage) -> Option<Vec<u8>> {
    let mut out = Cursor::new(Vec::new());
    image.write_to(&mut out, ImageFormat::Png).ok()?;
    Some(out.into_inner())
}

/// Quality high enough that small text keeps its edges.
fn jpeg(image: &DynamicImage) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    image.to_rgb8().write_with_encoder(JpegEncoder::new_with_quality(&mut out, 88)).ok()?;
    Some(out)
}

/// Makes the thumbnails of images just kept, off the caller's thread.
pub fn make_later(images: Vec<PathBuf>, dir: PathBuf) {
    let images: Vec<PathBuf> = images.into_iter().filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(wanted)).collect();
    if images.is_empty() {
        return;
    }
    std::thread::spawn(move || {
        for image in images {
            let _ = thumbnail(&image, &dir);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgb, Rgba};

    fn noisy(w: u32, h: u32) -> DynamicImage {
        DynamicImage::ImageRgb8(ImageBuffer::from_fn(w, h, |x, y| Rgb([(x * 7 + y * 13) as u8, (x ^ y) as u8, (x * y) as u8])))
    }

    #[test]
    fn makes_a_small_jpeg_of_a_big_screenshot_once() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("shot.png");
        noisy(2400, 1600).save(&src).unwrap();
        let thumbs = tmp.path().join("thumbs");
        let (path, kind) = thumbnail(&src, &thumbs).unwrap();
        assert_eq!(kind, "image/jpeg");
        let made = image::open(&path).unwrap();
        assert_eq!((made.width(), made.height()), (720, 480));
        assert!(std::fs::metadata(&path).unwrap().len() < std::fs::metadata(&src).unwrap().len());
        // Kept: asked again, the same file.
        let modified = std::fs::metadata(&path).unwrap().modified().unwrap();
        assert_eq!(thumbnail(&src, &thumbs).unwrap().0, path);
        assert_eq!(std::fs::metadata(&path).unwrap().modified().unwrap(), modified);
    }

    #[test]
    fn keeps_clear_parts_clear() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("cut.png");
        DynamicImage::ImageRgba8(ImageBuffer::from_fn(1600, 1600, |x, y| Rgba([(x * 7) as u8, (y * 3) as u8, (x ^ y) as u8, if x < 800 { 0 } else { 255 }]))).save(&src).unwrap();
        let (path, kind) = thumbnail(&src, &tmp.path().join("thumbs")).unwrap();
        assert_eq!(kind, "image/png");
        assert!(image::open(&path).unwrap().color().has_alpha());
    }

    #[test]
    fn leaves_small_images_and_others_alone() {
        let tmp = tempfile::tempdir().unwrap();
        let small = tmp.path().join("icon.png");
        noisy(64, 64).save(&small).unwrap();
        assert!(thumbnail(&small, &tmp.path().join("thumbs")).is_none());
        let gif = tmp.path().join("moving.gif");
        std::fs::write(&gif, vec![0u8; 200 * 1024]).unwrap();
        assert!(thumbnail(&gif, &tmp.path().join("thumbs")).is_none());
        let broken = tmp.path().join("broken.png");
        std::fs::write(&broken, vec![7u8; 200 * 1024]).unwrap();
        assert!(thumbnail(&broken, &tmp.path().join("thumbs")).is_none());
    }
}
