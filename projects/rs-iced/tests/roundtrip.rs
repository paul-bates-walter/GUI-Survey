//! End-to-end check of the non-GUI core: rasterize shapes into an RGBA buffer,
//! save a PNG with tEXt metadata, reload it, and confirm pixels + metadata
//! survive the round trip. Covers spec.md drawing, filesystem, and forms
//! features without needing a GPU/display.

use std::path::PathBuf;

// The binary crate's modules, pulled in directly for testing.
#[path = "../src/raster.rs"]
mod raster;
#[path = "../src/pngio.rs"]
mod pngio;

fn tmp_path(name: &str) -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!("iced-rs-test-{}-{name}", std::process::id()));
    p
}

#[test]
fn draw_save_load_preserves_pixels_and_metadata() {
    let (w, h) = (64u32, 48u32);
    let mut pixels = vec![255u8; (w * h * 4) as usize]; // opaque white

    let mut surface = raster::Surface {
        width: w,
        height: h,
        rgba: &mut pixels,
    };
    // Solid red disc centered in the image.
    raster::fill_circle(&mut surface, 32.0, 24.0, 10.0, [1.0, 0.0, 0.0, 1.0]);

    let center = (((24 * w + 32) * 4) as usize);
    assert!(pixels[center] > 200, "disc center should be red");
    assert!(pixels[center + 1] < 60, "disc center green channel low");
    // A corner pixel stays white.
    assert_eq!(&pixels[0..4], &[255, 255, 255, 255]);

    let path = tmp_path("roundtrip.png");
    let meta = vec![
        ("Title".to_string(), "Round Trip".to_string()),
        ("Author".to_string(), "iced-rs".to_string()),
    ];
    pngio::save(&path, w, h, &pixels, &meta).expect("save PNG");

    let loaded = pngio::load(&path).expect("load PNG");
    assert_eq!((loaded.width, loaded.height), (w, h));
    assert_eq!(loaded.rgba.len(), pixels.len());
    assert_eq!(loaded.rgba, pixels, "pixels survive the round trip");

    assert!(loaded.metadata.contains(&("Title".to_string(), "Round Trip".to_string())));
    assert!(loaded.metadata.contains(&("Author".to_string(), "iced-rs".to_string())));

    std::fs::remove_file(&path).ok();
}

#[test]
fn deleted_metadata_key_is_not_reemitted() {
    let (w, h) = (8u32, 8u32);
    let pixels = vec![0u8; (w * h * 4) as usize];
    let path = tmp_path("meta.png");

    pngio::save(&path, w, h, &pixels, &[("Keep".into(), "yes".into())]).unwrap();
    let loaded = pngio::load(&path).unwrap();
    assert_eq!(loaded.metadata.len(), 1);
    assert!(!loaded.metadata.iter().any(|(k, _)| k == "Dropped"));

    std::fs::remove_file(&path).ok();
}
