//! File encoding detection and conversion utilities.
//!
//! Handles detection of UTF-8, UTF-16 (BOM or heuristic), and ASCII content.
//! Provides decode/encode helpers and line-ending normalization.

use std::borrow::Cow;

/// Detected encoding for a byte sequence.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
    Ascii,
    Unknown,
}

impl Encoding {
    pub fn is_utf8(self) -> bool {
        matches!(self, Encoding::Utf8 | Encoding::Ascii)
    }

    pub fn is_utf16(self) -> bool {
        matches!(self, Encoding::Utf16Le | Encoding::Utf16Be)
    }
}

/// Detect the encoding of a byte slice by inspecting BOM and content.
pub fn detect_encoding(data: &[u8]) -> Encoding {
    if data.len() >= 3 && data[0..3] == [0xEF, 0xBB, 0xBF] {
        return Encoding::Utf8;
    }
    if data.len() >= 2 && data[0..2] == [0xFF, 0xFE] {
        return Encoding::Utf16Le;
    }
    if data.len() >= 2 && data[0..2] == [0xFE, 0xFF] {
        return Encoding::Utf16Be;
    }
    if data.is_ascii() {
        return Encoding::Ascii;
    }
    // Heuristic: if the data is valid UTF-8, treat it as such.
    if std::str::from_utf8(data).is_ok() {
        return Encoding::Utf8;
    }
    // Check for UTF-16: look for many NUL bytes interleaved with ASCII.
    let null_count = data.iter().filter(|b| **b == 0).count();
    if null_count > data.len() / 4 && null_count < data.len() / 2 {
        // Check byte order: if even-indexed bytes tend to be NUL, it is UTF-16BE.
        let even_nulls = data.iter().step_by(2).filter(|b| **b == 0).count();
        let odd_nulls = data.iter().skip(1).step_by(2).filter(|b| **b == 0).count();
        if even_nulls > odd_nulls {
            return Encoding::Utf16Be;
        }
        return Encoding::Utf16Le;
    }
    Encoding::Unknown
}

/// Whether a BOM is present at the start of the byte slice.
pub fn has_bom(data: &[u8]) -> bool {
    (data.len() >= 3 && data[0..3] == [0xEF, 0xBB, 0xBF])
        || (data.len() >= 2 && data[0..2] == [0xFF, 0xFE])
        || (data.len() >= 2 && data[0..2] == [0xFE, 0xFF])
}

/// The BOM bytes for a given encoding, or None if the encoding has no BOM.
pub fn bom_bytes(encoding: Encoding) -> Option<&'static [u8]> {
    match encoding {
        Encoding::Utf8 => Some(&[0xEF, 0xBB, 0xBF]),
        Encoding::Utf16Le => Some(&[0xFF, 0xFE]),
        Encoding::Utf16Be => Some(&[0xFE, 0xFF]),
        Encoding::Ascii | Encoding::Unknown => None,
    }
}

/// Decode a byte slice into a String using the detected encoding.
///
/// For UTF-8/ASCII the bytes are used directly. For UTF-16 the data is
/// converted (with BOM stripped). Returns an error string on failure.
pub fn decode(data: &[u8]) -> Result<Cow<'_, str>, String> {
    match detect_encoding(data) {
        Encoding::Utf8 | Encoding::Ascii => {
            // Strip BOM if present.
            let content = if has_bom(data) { &data[3..] } else { data };
            Ok(Cow::Borrowed(std::str::from_utf8(content).map_err(|e| e.to_string())?))
        }
        Encoding::Utf16Le => {
            let slice = if data[0..2] == [0xFF, 0xFE] { &data[2..] } else { data };
            decode_utf16le(slice)
        }
        Encoding::Utf16Be => {
            let slice = if data[0..2] == [0xFE, 0xFF] { &data[2..] } else { data };
            decode_utf16be(slice)
        }
        Encoding::Unknown => Err("Unsupported or unrecognized encoding".into()),
    }
}

/// Encode a string as UTF-8 bytes.
pub fn encode_to_utf8(text: &str) -> Vec<u8> {
    text.as_bytes().to_vec()
}

/// Heuristic: does the file look like text rather than binary data?
///
/// Scans the first 8 KiB and returns false if any NUL byte is found, or if more
/// than 30 % of the bytes are non-text (control characters other than tab/newline).
pub fn is_text_file(data: &[u8]) -> bool {
    let sample = if data.len() > 8192 { &data[..8192] } else { data };
    if sample.contains(&0) {
        return false;
    }
    let non_text = sample
        .iter()
        .filter(|b| !b.is_ascii_graphic() && **b != 0x09 && **b != 0x0A && **b != 0x0D)
        .count();
    if sample.is_empty() {
        return true;
    }
    (non_text as f32 / sample.len() as f32) < 0.30
}

/// Convert line endings: replace `\r\n` with `\n`.
pub fn normalize_newlines(text: &str) -> String {
    text.replace("\r\n", "\n")
}

/// Convert all line endings to a specific style (`\n`, `\r\n`, or `\r`).
pub fn convert_line_endings(text: &str, target: &str) -> String {
    let normalized = normalize_newlines(text);
    normalized.replace('\n', target)
}

fn decode_utf16le(data: &[u8]) -> Result<Cow<'_, str>, String> {
    if data.len() % 2 != 0 {
        return Err("UTF-16LE data has odd length".into());
    }
    let mut u16s = Vec::with_capacity(data.len() / 2);
    for chunk in data.chunks_exact(2) {
        u16s.push(u16::from_le_bytes([chunk[0], chunk[1]]));
    }
    String::from_utf16(&u16s).map(|s| Cow::Owned(s)).map_err(|e| e.to_string())
}

fn decode_utf16be(data: &[u8]) -> Result<Cow<'_, str>, String> {
    if data.len() % 2 != 0 {
        return Err("UTF-16BE data has odd length".into());
    }
    let mut u16s = Vec::with_capacity(data.len() / 2);
    for chunk in data.chunks_exact(2) {
        u16s.push(u16::from_be_bytes([chunk[0], chunk[1]]));
    }
    String::from_utf16(&u16s).map(|s| Cow::Owned(s)).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_utf8_bom() {
        let data = [0xEF, 0xBB, 0xBF, b'h', b'i'];
        assert_eq!(detect_encoding(&data), Encoding::Utf8);
    }

    #[test]
    fn test_detect_utf16le_bom() {
        let data = [0xFF, 0xFE, b'h', 0x00];
        assert_eq!(detect_encoding(&data), Encoding::Utf16Le);
    }

    #[test]
    fn test_detect_utf16be_bom() {
        let data = [0xFE, 0xFF, 0x00, b'h'];
        assert_eq!(detect_encoding(&data), Encoding::Utf16Be);
    }

    #[test]
    fn test_detect_ascii() {
        assert_eq!(detect_encoding(b"hello"), Encoding::Ascii);
    }

    #[test]
    fn test_has_bom() {
        assert!(has_bom(&[0xEF, 0xBB, 0xBF]));
        assert!(has_bom(&[0xFF, 0xFE]));
        assert!(has_bom(&[0xFE, 0xFF]));
        assert!(!has_bom(b"hello"));
    }

    #[test]
    fn test_decode_utf8() {
        let data = b"hello world";
        let result = decode(data).unwrap();
        assert_eq!(result, "hello world");
    }

    #[test]
    fn test_decode_utf8_bom_stripped() {
        let data = [0xEF, 0xBB, 0xBF, b'h', b'i'];
        let result = decode(&data).unwrap();
        assert_eq!(result, "hi");
    }

    #[test]
    fn test_decode_utf16le() {
        let mut data = vec![0xFF, 0xFE]; // BOM
        for b in "hi".encode_utf16() {
            data.extend_from_slice(&b.to_le_bytes());
        }
        let result = decode(&data).unwrap();
        assert_eq!(result, "hi");
    }

    #[test]
    fn test_encode_to_utf8() {
        assert_eq!(encode_to_utf8("hello"), b"hello");
    }

    #[test]
    fn test_is_text_file() {
        assert!(is_text_file(b"hello world\nthis is text\n"));
        assert!(!is_text_file(&[0x00, 0x01, 0x02, 0x03]));
        assert!(is_text_file(b""));
    }

    #[test]
    fn test_normalize_newlines() {
        assert_eq!(normalize_newlines("a\r\nb\nc"), "a\nb\nc");
        assert_eq!(normalize_newlines("a\nb"), "a\nb");
    }

    #[test]
    fn test_convert_line_endings() {
        assert_eq!(convert_line_endings("a\nb", "\r\n"), "a\r\nb");
        assert_eq!(convert_line_endings("a\r\nb", "\n"), "a\nb");
    }

    #[test]
    fn test_bom_bytes() {
        assert_eq!(bom_bytes(Encoding::Utf8), Some(&[0xEF, 0xBB, 0xBF]));
        assert_eq!(bom_bytes(Encoding::Utf16Le), Some(&[0xFF, 0xFE]));
        assert_eq!(bom_bytes(Encoding::Ascii), None);
    }
}
