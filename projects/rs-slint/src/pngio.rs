//! PNG load/save with tEXt metadata (spec: Filesystem Integration + Forms).
//!
//! Pixels are decoded via the `image` crate (which normalizes palette / bit
//! depth to RGBA8 for us) while textual metadata is read and written through
//! the lower-level `png` crate, because `image` does not surface tEXt chunks.

use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

/// A decoded picture plus its tEXt key/value pairs.
pub struct Loaded {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
    pub metadata: Vec<(String, String)>,
}

/// Read a PNG into RGBA8 and pull out its tEXt entries.
pub fn load(path: &Path) -> Result<Loaded, String> {
    let dynimg = image::open(path).map_err(|e| format!("decode failed: {e}"))?;
    let rgba_img = dynimg.to_rgba8();
    let (width, height) = rgba_img.dimensions();

    let metadata = read_text_chunks(path).unwrap_or_default();

    Ok(Loaded {
        width,
        height,
        rgba: rgba_img.into_raw(),
        metadata,
    })
}

/// Re-decode only the tEXt chunks from a PNG file.
fn read_text_chunks(path: &Path) -> Result<Vec<(String, String)>, String> {
    let file = File::open(path).map_err(|e| e.to_string())?;
    let decoder = png::Decoder::new(file);
    let reader = decoder.read_info().map_err(|e| e.to_string())?;
    let info = reader.info();

    let mut out = Vec::new();
    // Uncompressed tEXt chunks.
    for chunk in &info.uncompressed_latin1_text {
        out.push((chunk.keyword.clone(), chunk.text.clone()));
    }
    // Compressed zTXt chunks, decompressed on demand.
    for chunk in &info.compressed_latin1_text {
        if let Ok(text) = chunk.get_text() {
            out.push((chunk.keyword.clone(), text));
        }
    }
    // International iTXt chunks.
    for chunk in &info.utf8_text {
        if let Ok(text) = chunk.get_text() {
            out.push((chunk.keyword.clone(), text));
        }
    }
    Ok(out)
}

/// Write RGBA8 pixels to a PNG, embedding the given key/value pairs as tEXt
/// chunks. The file is rebuilt from scratch, so keys the user deleted are not
/// re-emitted.
pub fn save(
    path: &Path,
    width: u32,
    height: u32,
    rgba: &[u8],
    metadata: &[(String, String)],
) -> Result<(), String> {
    let file = File::create(path).map_err(|e| e.to_string())?;
    let writer = BufWriter::new(file);

    let mut encoder = png::Encoder::new(writer, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);

    // tEXt chunks must be added before the header is written.
    for (key, value) in metadata {
        let key = key.trim();
        if key.is_empty() {
            continue;
        }
        // PNG keywords are latin-1 and limited to 1..=79 bytes.
        let key: String = key.chars().take(79).collect();
        encoder
            .add_text_chunk(key, value.clone())
            .map_err(|e| e.to_string())?;
    }

    let mut header = encoder.write_header().map_err(|e| e.to_string())?;
    header.write_image_data(rgba).map_err(|e| e.to_string())?;
    Ok(())
}
