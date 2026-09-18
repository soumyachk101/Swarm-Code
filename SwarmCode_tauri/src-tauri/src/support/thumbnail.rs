//! Thumbnail cache for downsampled image attachments.
//!
//! Thumbnails are generated off the main thread and kept for reuse, so
//! scrolling past a message with images never reads or decodes a file while
//! drawing.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use image::{imageops::FilterType, DynamicImage, ImageFormat};
use tokio::sync::RwLock;

/// A generated thumbnail.
#[derive(Debug, Clone)]
pub struct Thumbnail {
    pub path: PathBuf,
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub format: ThumbnailFormat,
    pub created_at: Instant,
}

/// Encoded image format for thumbnails.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThumbnailFormat {
    Png,
    Jpeg,
}

impl ThumbnailFormat {
    pub fn extension(self) -> &'static str {
        match self {
            ThumbnailFormat::Png => "png",
            ThumbnailFormat::Jpeg => "jpg",
        }
    }
}

#[derive(Debug)]
pub struct ThumbnailCache {
    cache: Arc<RwLock<HashMap<String, Thumbnail>>>,
    max_size: usize,
    max_age: Duration,
    default_format: ThumbnailFormat,
}

impl Clone for ThumbnailCache {
    fn clone(&self) -> Self {
        Self {
            cache: Arc::clone(&self.cache),
            max_size: self.max_size,
            max_age: self.max_age,
            default_format: self.default_format,
        }
    }
}

impl ThumbnailCache {
    pub fn new(max_size: usize, max_age: Duration) -> Self {
        Self {
            cache: Arc::new(RwLock::new(HashMap::new())),
            max_size: max_size.max(1),
            max_age,
            default_format: ThumbnailFormat::Png,
        }
    }

    /// Construct a cache that emits JPEG thumbnails.
    pub fn with_jpeg(mut self) -> Self {
        self.default_format = ThumbnailFormat::Jpeg;
        self
    }

    /// The cache key: path + pixel size, mirroring the Swift implementation's
    /// `"<path>#<pixels>"` scheme.
    pub fn cache_key(path: &str, max_pixels: u32) -> String {
        format!("{}#{}", path, max_pixels)
    }

    /// Look up an existing thumbnail, if any.
    pub async fn get(&self, path: &str, max_pixels: u32) -> Option<Thumbnail> {
        let key = Self::cache_key(path, max_pixels);
        let cache = self.cache.read().await;
        cache.get(&key).cloned()
    }

    /// Store a thumbnail in the cache, evicting the oldest entry when full.
    pub async fn put(&self, thumbnail: Thumbnail, max_pixels: u32) {
        let key = Self::cache_key(thumbnail.path.to_string_lossy().as_ref(), max_pixels);
        let mut cache = self.cache.write().await;
        if cache.len() >= self.max_size {
            // Evict the oldest entry by created_at.
            if let Some(oldest_key) = cache
                .iter()
                .min_by_key(|(_, v)| v.created_at)
                .map(|(k, _)| k.clone())
            {
                cache.remove(&oldest_key);
            }
        }
        cache.insert(key, thumbnail);
    }

    /// Generate a thumbnail from the given source file. The returned bytes are
    /// ready to be decoded as an image.
    pub async fn generate_thumbnail(
        &self,
        path: &Path,
        max_pixels: u32,
    ) -> Result<Thumbnail, String> {
        let bytes = tokio::fs::read(path)
            .await
            .map_err(|e| format!("Failed to read image file: {}", e))?;
        self.generate_thumbnail_from_bytes(&bytes, path.to_path_buf(), max_pixels)
            .await
    }

    /// Generate a thumbnail from an in-memory byte buffer.
    pub async fn generate_thumbnail_from_bytes(
        &self,
        bytes: &[u8],
        path: PathBuf,
        max_pixels: u32,
    ) -> Result<Thumbnail, String> {
        let img = image::load_from_memory(bytes)
            .map_err(|e| format!("Failed to decode image: {}", e))?;
        let resized = resize_to_fit(img, max_pixels);
        let data = match self.default_format {
            ThumbnailFormat::Png => encode_png(&resized)?,
            ThumbnailFormat::Jpeg => encode_jpeg(&resized)?,
        };
        Ok(Thumbnail {
            path,
            data,
            width: resized.width(),
            height: resized.height(),
            format: self.default_format,
            created_at: Instant::now(),
        })
    }

    /// Convenience: get a cached thumbnail, generating and caching it if
    /// absent.
    pub async fn get_or_generate(
        &self,
        path: &Path,
        max_pixels: u32,
    ) -> Result<Thumbnail, String> {
        let path_str = path.to_string_lossy().to_string();
        if let Some(cached) = self.get(&path_str, max_pixels).await {
            return Ok(cached);
        }
        let thumbnail = self.generate_thumbnail(path, max_pixels).await?;
        self.put(thumbnail.clone(), max_pixels).await;
        Ok(thumbnail)
    }

    /// Evict every entry older than the configured TTL.
    pub async fn evict_stale(&self) {
        let mut cache = self.cache.write().await;
        cache.retain(|_, entry| entry.created_at.elapsed() < self.max_age);
    }

    /// The number of entries currently in the cache.
    pub async fn len(&self) -> usize {
        self.cache.read().await.len()
    }

    /// Whether the cache has no entries.
    pub async fn is_empty(&self) -> bool {
        self.cache.read().await.is_empty()
    }

    /// Drop every cached thumbnail.
    pub async fn clear(&self) {
        self.cache.write().await.clear();
    }

    /// Image formats this cache can decode.
    pub fn supported_formats() -> &'static [&'static str] {
        &[
            "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "ico",
            "hdr", "pnm", "pgm", "ppm", "tga", "dds", "exr",
        ]
    }

    /// Whether the given extension corresponds to a supported image format.
    pub fn supports_extension(ext: &str) -> bool {
        Self::supported_formats().contains(&ext.to_ascii_lowercase().as_str())
    }

    /// The format hint for a file path's extension, if known.
    pub fn format_from_path(path: &Path) -> Option<ImageFormat> {
        let ext = path.extension()?.to_string_lossy().to_ascii_lowercase();
        ImageFormat::from_extension(ext)
    }
}

fn resize_to_fit(img: DynamicImage, max_pixels: u32) -> DynamicImage {
    let (w, h) = (img.width(), img.height());
    let longest = w.max(h);
    if longest <= max_pixels || max_pixels == 0 {
        return img;
    }
    let scale = max_pixels as f32 / longest as f32;
    let new_w = ((w as f32) * scale).round().max(1.0) as u32;
    let new_h = ((h as f32) * scale).round().max(1.0) as u32;
    img.resize(new_w, new_h, FilterType::Lanczos3)
}

fn encode_png(img: &DynamicImage) -> Result<Vec<u8>, String> {
    let mut buf = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut buf);
    img.write_to(&mut cursor, ImageFormat::Png)
        .map_err(|e| format!("PNG encode failed: {}", e))?;
    Ok(buf)
}

fn encode_jpeg(img: &DynamicImage) -> Result<Vec<u8>, String> {
    let mut buf = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut buf);
    img.write_to(&mut cursor, ImageFormat::Jpeg)
        .map_err(|e| format!("JPEG encode failed: {}", e))?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgba};

    fn make_test_image(w: u32, h: u32) -> Vec<u8> {
        let img: ImageBuffer<Rgba<u8>, Vec<u8>> =
            ImageBuffer::from_fn(w, h, |x, y| Rgba([x as u8, y as u8, 128, 255]));
        let mut buf = Vec::new();
        let mut cursor = std::io::Cursor::new(&mut buf);
        img.write_to(&mut cursor, ImageFormat::Png).unwrap();
        buf
    }

    #[tokio::test]
    async fn test_cache_key() {
        assert_eq!(ThumbnailCache::cache_key("foo.png", 64), "foo.png#64");
    }

    #[tokio::test]
    async fn test_generate_thumbnail_from_bytes() {
        let cache = ThumbnailCache::new(10, Duration::from_secs(60));
        let bytes = make_test_image(200, 100);
        let thumb = cache
            .generate_thumbnail_from_bytes(&bytes, PathBuf::from("test.png"), 50)
            .await
            .unwrap();
        assert_eq!(thumb.width, 50);
        assert_eq!(thumb.height, 25);
        assert!(!thumb.data.is_empty());
        assert_eq!(thumb.format, ThumbnailFormat::Png);
    }

    #[tokio::test]
    async fn test_get_or_generate() {
        let cache = ThumbnailCache::new(10, Duration::from_secs(60));
        let bytes = make_test_image(80, 40);
        // Use a temp file so get_or_generate can read it.
        let tmp = std::env::temp_dir().join("swarmcode_thumb_test.png");
        std::fs::write(&tmp, &bytes).unwrap();
        let first = cache.get_or_generate(&tmp, 40).await.unwrap();
        let second = cache.get_or_generate(&tmp, 40).await.unwrap();
        assert_eq!(first.width, second.width);
        assert_eq!(first.height, second.height);
        let _ = std::fs::remove_file(&tmp);
    }

    #[tokio::test]
    async fn test_evict_stale() {
        let cache = ThumbnailCache::new(10, Duration::from_millis(1));
        let bytes = make_test_image(40, 40);
        let thumb = cache
            .generate_thumbnail_from_bytes(&bytes, PathBuf::from("t.png"), 20)
            .await
            .unwrap();
        cache.put(thumb, 20).await;
        std::thread::sleep(Duration::from_millis(5));
        cache.evict_stale().await;
        assert!(cache.is_empty().await);
    }

    #[test]
    fn test_supported_formats() {
        assert!(ThumbnailCache::supports_extension("png"));
        assert!(ThumbnailCache::supports_extension("JPG"));
        assert!(!ThumbnailCache::supports_extension("zip"));
    }
}
