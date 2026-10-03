//! The Rust station's thumbnails and ThumbHashes (thumbs.rs) of the test images, for the station in TypeScript to answer
//! the same (station/test/thumbs.test.ts). Writes into <out>/ the images the TypeScript test cannot make itself (JPEG
//! with EXIF, WebP), and <out>/golden.json: for each test image, its thumbnail (type, SHA-256, size) or null, and its
//! ThumbHash or null. The PNG ones are made in a temporary directory: the test makes them too, with the same pixels.
//!   cd mesh && cargo run --release -p stillfail-app --example thumbs_golden -- ../station/test/fixtures/thumbs

use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, ImageBuffer, Rgb, Rgba};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use stillfail_app::store::Attachment;
use stillfail_app::thumbs;

/// As thumbs.rs's tests make them (the test makes the same).
fn noisy(w: u32, h: u32) -> DynamicImage {
    DynamicImage::ImageRgb8(ImageBuffer::from_fn(w, h, |x, y| Rgb([(x * 7 + y * 13) as u8, (x ^ y) as u8, (x * y) as u8])))
}

/// Something like a photo: smooth, with a little grain.
fn photo(w: u32, h: u32) -> DynamicImage {
    DynamicImage::ImageRgb8(ImageBuffer::from_fn(w, h, |x, y| {
        let wave = ((x as f32 / 40.0).sin() * 60.0 + 128.0) as u32;
        Rgb([(x * 255 / w + (x * y) % 5) as u8, (y * 255 / h) as u8, (wave + (x + 3 * y) % 3) as u8])
    }))
}

/// A JPEG whose EXIF says it is seen turned a quarter (orientation 6), as thumbs.rs's test writes it.
fn turned_jpeg(image: &DynamicImage, quality: u8) -> Vec<u8> {
    let mut jpeg = Vec::new();
    image.to_rgb8().write_with_encoder(JpegEncoder::new_with_quality(&mut jpeg, quality)).unwrap();
    let exif: &[u8] = &[b'E', b'x', b'i', b'f', 0, 0, b'M', b'M', 0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, 0, 0, 0, 0];
    let mut app1 = vec![0xFF, 0xE1];
    app1.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
    app1.extend_from_slice(exif);
    let mut file = jpeg[..2].to_vec();
    file.extend(app1);
    file.extend_from_slice(&jpeg[2..]);
    file
}

#[tokio::main]
async fn main() {
    let out = std::path::PathBuf::from(std::env::args().nth(1).expect("usage: thumbs_golden <out dir>"));
    std::fs::create_dir_all(&out).unwrap();
    let tmp = tempfile::tempdir().unwrap();
    let made = tmp.path().join("made");
    std::fs::create_dir_all(&made).unwrap();
    // Made by the test too.
    noisy(1200, 800).save(made.join("shot.png")).unwrap();
    noisy(500, 1500).save(made.join("tall.png")).unwrap();
    DynamicImage::ImageRgba8(ImageBuffer::from_fn(1000, 1000, |x, y| Rgba([(x * 7) as u8, (y * 3) as u8, (x ^ y) as u8, if x < 500 { 0 } else { 255 }]))).save(made.join("cut.png")).unwrap();
    noisy(64, 64).save(made.join("icon.png")).unwrap();
    DynamicImage::ImageRgba8(ImageBuffer::from_fn(80, 40, |x, _| Rgba([200, 60, 20, if x < 40 { 0 } else { 255 }]))).save(made.join("clear.png")).unwrap();
    std::fs::write(made.join("broken.png"), vec![7u8; 200 * 1024]).unwrap();
    std::fs::write(made.join("moving.gif"), vec![0u8; 200 * 1024]).unwrap();
    std::fs::write(made.join("notes.txt"), "hi").unwrap();
    // Kept as fixtures.
    std::fs::write(out.join("photo.jpg"), turned_jpeg(&photo(960, 640), 92)).unwrap();
    std::fs::write(out.join("photo-small.jpg"), turned_jpeg(&noisy(40, 20), 90)).unwrap();
    noisy(64, 64).save(out.join("icon.webp")).unwrap();
    photo(760, 300).save(out.join("wide.webp")).unwrap();
    let names = ["shot.png", "tall.png", "cut.png", "icon.png", "clear.png", "broken.png", "moving.gif", "notes.txt", "photo.jpg", "photo-small.jpg", "icon.webp", "wide.webp"];
    let path_of = |name: &str| if out.join(name).is_file() { out.join(name) } else { made.join(name) };
    let thumbs_dir = tmp.path().join("thumbs");
    let files = names.iter().map(|n| { let p = path_of(n); Attachment { name: n.to_string(), path: p.to_string_lossy().into_owned(), size: 0, width: None, height: None, thumbhash: None } }).collect();
    let kept = thumbs::keep(files, tmp.path().join("kept")).await;
    let mut golden = Map::new();
    for (name, file) in names.iter().zip(kept) {
        let path = path_of(name);
        let thumbnail = thumbs::thumbnail(&path, &thumbs_dir).map(|(p, kind)| {
            let bytes = std::fs::read(&p).unwrap();
            let (w, h) = image::image_dimensions(&p).unwrap();
            json!({ "type": kind, "sha256": hex::encode(Sha256::digest(&bytes)), "bytes": bytes.len(), "width": w, "height": h })
        });
        golden.insert(name.to_string(), json!({ "size": std::fs::metadata(&path).unwrap().len(), "thumbnail": thumbnail, "thumbhash": file.thumbhash }));
    }
    let text = serde_json::to_string_pretty(&Value::Object(golden)).unwrap() + "\n";
    std::fs::write(out.join("golden.json"), text).unwrap();
}
