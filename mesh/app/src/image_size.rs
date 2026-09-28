//! An image's pixel size from its first bytes: PNG, GIF, JPEG and WebP, the formats pages show inline. Nothing is
//! decoded; unknown files give None.

use std::io::Read;
use std::path::Path;

pub fn image_size(path: &Path) -> Option<(u32, u32)> {
    let mut head = vec![0u8; 64 * 1024];
    let n = std::fs::File::open(path).ok()?.read(&mut head).ok()?;
    size_of(&head[..n])
}

pub fn size_of(b: &[u8]) -> Option<(u32, u32)> {
    let ok = |w: u32, h: u32| (w > 0 && h > 0).then_some((w, h));
    let be32 = |i: usize| u32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]);
    let le32 = |i: usize| u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]);
    let be16 = |i: usize| u16::from_be_bytes([b[i], b[i + 1]]) as u32;
    let le16 = |i: usize| u16::from_le_bytes([b[i], b[i + 1]]) as u32;
    let le24 = |i: usize| b[i] as u32 | (b[i + 1] as u32) << 8 | (b[i + 2] as u32) << 16;
    if b.len() >= 24 && be32(0) == 0x8950_4e47 && &b[12..16] == b"IHDR" {
        return ok(be32(16), be32(20));
    }
    if b.len() >= 10 && &b[0..3] == b"GIF" {
        return ok(le16(6), le16(8));
    }
    if b.len() >= 30 && &b[0..4] == b"RIFF" && &b[8..12] == b"WEBP" {
        return match &b[12..16] {
            b"VP8 " => ok(le16(26) & 0x3fff, le16(28) & 0x3fff),
            b"VP8L" => {
                let v = le32(21);
                ok((v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1)
            }
            b"VP8X" => ok(1 + le24(24), 1 + le24(27)),
            _ => None,
        };
    }
    if b.len() >= 4 && b[0] == 0xff && b[1] == 0xd8 {
        // Walk the markers to the first start-of-frame, which carries the size.
        let mut i = 2;
        while i + 9 < b.len() {
            if b[i] != 0xff {
                i += 1;
                continue;
            }
            let marker = b[i + 1];
            if marker == 0xd8 || marker == 0x01 || (0xd0..=0xd7).contains(&marker) {
                i += 2;
                continue;
            }
            let length = be16(i + 2) as usize;
            if (0xc0..=0xcf).contains(&marker) && marker != 0xc4 && marker != 0xc8 && marker != 0xcc {
                return ok(be16(i + 7), be16(i + 5));
            }
            i += 2 + length;
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_are_read_from_each_formats_header() {
        let mut png = vec![0x89, b'P', b'N', b'G', 13, 10, 26, 10, 0, 0, 0, 13];
        png.extend(b"IHDR");
        png.extend(640u32.to_be_bytes());
        png.extend(480u32.to_be_bytes());
        assert_eq!(size_of(&png), Some((640, 480)));
        let gif = [b'G', b'I', b'F', b'8', b'9', b'a', 10, 0, 20, 0];
        assert_eq!(size_of(&gif), Some((10, 20)));
        let mut jpeg = vec![0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, 0xff, 0xc0, 0, 17, 8];
        jpeg.extend(300u16.to_be_bytes());
        jpeg.extend(200u16.to_be_bytes());
        jpeg.extend([0; 8]);
        assert_eq!(size_of(&jpeg), Some((200, 300)));
        assert_eq!(size_of(b"plain text"), None);
    }
}
