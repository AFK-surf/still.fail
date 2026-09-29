//! Small copies of the images sent in chats, for the chat to show: a chat of screenshots would otherwise have pages
//! take in megabytes to show each at a few hundred pixels. Made when an image is kept (and on first asking for one kept
//! before), in the station's data directory, by the image's path; the image itself stays as it was, for the preview.
//! And each image's ThumbHash, kept with the message: a blurred likeness of it, a few dozen bytes, shown until it loads.

use std::io::Cursor;
use std::path::{Path, PathBuf};

use base64::Engine;
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader};
use sha2::{Digest, Sha256};

use crate::store::Attachment;

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
    let len = std::fs::metadata(image).ok()?.len();
    if len <= SMALL {
        return None;
    }
    let id = id_of(image);
    kept(dir, &id).or_else(|| make(decode(image)?, len, dir, &id))
}

fn id_of(image: &Path) -> String {
    hex::encode(&Sha256::digest(image.to_string_lossy().as_bytes())[..16])
}

fn kept(dir: &Path, id: &str) -> Option<(PathBuf, &'static str)> {
    [("jpg", "image/jpeg"), ("png", "image/png")].into_iter().map(|(ext, kind)| (dir.join(format!("{id}.{ext}")), kind)).find(|(path, _)| path.is_file())
}

/// The image as it is seen: turned as its camera says (a photo's EXIF), which a copy without that note must do itself.
fn decode(image: &Path) -> Option<DynamicImage> {
    let mut decoder = ImageReader::open(image).ok()?.with_guessed_format().ok()?.into_decoder().ok()?;
    let orientation = decoder.orientation().ok();
    let mut decoded = DynamicImage::from_decoder(decoder).ok()?;
    if let Some(orientation) = orientation {
        decoded.apply_orientation(orientation);
    }
    Some(decoded)
}

fn make(decoded: DynamicImage, len: u64, dir: &Path, id: &str) -> Option<(PathBuf, &'static str)> {
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
    if bytes.len() as u64 >= len {
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

/// The image's ThumbHash (base64), taken from it at most 100px across, as the format wants.
fn hash(image: &DynamicImage) -> String {
    let small = image.thumbnail(100, 100).to_rgba8();
    let bytes = thumbhash::rgba_to_thumb_hash(small.width() as usize, small.height() as usize, small.as_raw());
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Readies the images of a message about to be kept: each is decoded once, for its ThumbHash, given now (the message
/// carries it), and its thumbnail, made after, off the caller's thread. Files not readable as images stay as they came.
pub async fn keep(files: Vec<Attachment>, dir: PathBuf) -> Vec<Attachment> {
    if !files.iter().any(|f| wanted(&f.name)) {
        return files;
    }
    let given = files.clone();
    tokio::task::spawn_blocking(move || {
        let mut files = files;
        let mut later = Vec::new();
        for file in files.iter_mut().filter(|f| wanted(&f.name)) {
            let path = PathBuf::from(&file.path);
            let Some(decoded) = decode(&path) else { continue };
            file.thumbhash = Some(hash(&decoded));
            let len = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            if len > SMALL {
                later.push((id_of(&path), len, decoded));
            }
        }
        if !later.is_empty() {
            std::thread::spawn(move || {
                for (id, len, decoded) in later {
                    if kept(&dir, &id).is_none() {
                        let _ = make(decoded, len, &dir, &id);
                    }
                }
            });
        }
        files
    })
    .await
    .unwrap_or(given)
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

    fn sent(path: &Path) -> Attachment {
        Attachment { name: path.file_name().unwrap().to_string_lossy().into_owned(), path: path.to_string_lossy().into_owned(), size: 0, width: None, height: None, thumbhash: None }
    }

    #[tokio::test]
    async fn gives_images_a_thumbhash_and_makes_their_thumbnails() {
        let tmp = tempfile::tempdir().unwrap();
        let (big, small, clear) = (tmp.path().join("shot.png"), tmp.path().join("icon.webp"), tmp.path().join("cut.png"));
        noisy(2400, 1600).save(&big).unwrap();
        noisy(64, 64).save(&small).unwrap();
        DynamicImage::ImageRgba8(ImageBuffer::from_fn(80, 40, |x, _| Rgba([200, 60, 20, if x < 40 { 0 } else { 255 }]))).save(&clear).unwrap();
        let notes = tmp.path().join("notes.txt");
        std::fs::write(&notes, "hi").unwrap();
        let broken = tmp.path().join("broken.jpg");
        std::fs::write(&broken, vec![7u8; 1024]).unwrap();
        let thumbs = tmp.path().join("thumbs");
        let files = keep(vec![sent(&big), sent(&small), sent(&clear), sent(&notes), sent(&broken)], thumbs.clone()).await;
        for file in &files[..3] {
            let bytes = base64::engine::general_purpose::STANDARD.decode(file.thumbhash.as_ref().unwrap()).unwrap();
            assert!(bytes.len() < 40, "{}: {} bytes", file.name, bytes.len());
            // Its shape comes with it, roughly (more roughly with clear parts).
            let ratio = thumbhash::thumb_hash_to_approximate_aspect_ratio(&bytes).unwrap();
            let (w, h) = image::image_dimensions(&file.path).unwrap();
            assert!((ratio / (w as f32 / h as f32) - 1.0).abs() < 0.25, "{}: {ratio}", file.name);
        }
        assert_eq!((files[3].thumbhash.as_deref(), files[4].thumbhash.as_deref()), (None, None));
        // The big one's thumbnail comes after, as if asked for.
        let id = id_of(&big);
        for _ in 0..200 {
            if kept(&thumbs, &id).is_some() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert_eq!(kept(&thumbs, &id).unwrap().1, "image/jpeg");
        assert!(kept(&thumbs, &id_of(&small)).is_none());
    }

    #[test]
    fn turns_a_photo_as_its_camera_says() {
        let tmp = tempfile::tempdir().unwrap();
        let src = tmp.path().join("photo.jpg");
        // A 40×20 JPEG whose EXIF says it is seen turned a quarter (orientation 6): 20×40.
        let mut jpeg = Vec::new();
        noisy(40, 20).to_rgb8().write_with_encoder(JpegEncoder::new_with_quality(&mut jpeg, 90)).unwrap();
        let exif: &[u8] = &[
            b'E', b'x', b'i', b'f', 0, 0, b'M', b'M', 0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0, 0, 0, 0,
        ];
        let mut app1 = vec![0xFF, 0xE1];
        app1.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
        app1.extend_from_slice(exif);
        let mut file = jpeg[..2].to_vec();
        file.extend(app1);
        file.extend_from_slice(&jpeg[2..]);
        std::fs::write(&src, file).unwrap();
        let seen = decode(&src).unwrap();
        assert_eq!((seen.width(), seen.height()), (20, 40));
    }
}
