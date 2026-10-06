//! Software rasterizer for the drawing surface.
//!
//! The source of truth for the picture is a plain RGBA8 byte buffer. Shapes
//! are blended straight into it so that saving a PNG is just "write the bytes"
//! and needs no read-back from the GPU. Functions here are free functions over
//! that buffer (no drawing "object"), in keeping with the repo's functional
//! style.

/// A mutable view over an RGBA8 image buffer plus its dimensions.
pub struct Surface<'a> {
    pub width: u32,
    pub height: u32,
    pub rgba: &'a mut [u8],
}

/// Alpha-blend a single premultiplied-by-coverage source color onto one pixel.
fn blend_pixel(surface: &mut Surface, x: i32, y: i32, color: [f32; 4], coverage: f32) {
    if x < 0 || y < 0 || x >= surface.width as i32 || y >= surface.height as i32 {
        return;
    }
    let idx = ((y as usize) * (surface.width as usize) + (x as usize)) * 4;
    let src_a = color[3] * coverage;
    if src_a <= 0.0 {
        return;
    }
    for c in 0..3 {
        let dst = surface.rgba[idx + c] as f32 / 255.0;
        let out = color[c] * src_a + dst * (1.0 - src_a);
        surface.rgba[idx + c] = (out * 255.0).round().clamp(0.0, 255.0) as u8;
    }
    let dst_a = surface.rgba[idx + 3] as f32 / 255.0;
    let out_a = src_a + dst_a * (1.0 - src_a);
    surface.rgba[idx + 3] = (out_a * 255.0).round().clamp(0.0, 255.0) as u8;
}

/// Fill a solid disc centered at (cx, cy). Edge pixels get analytic coverage
/// for a bit of anti-aliasing.
pub fn fill_circle(surface: &mut Surface, cx: f32, cy: f32, radius: f32, color: [f32; 4]) {
    if radius <= 0.0 {
        return;
    }
    let min_x = (cx - radius - 1.0).floor() as i32;
    let max_x = (cx + radius + 1.0).ceil() as i32;
    let min_y = (cy - radius - 1.0).floor() as i32;
    let max_y = (cy + radius + 1.0).ceil() as i32;
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            // 1px-wide linear coverage falloff at the boundary.
            let coverage = (radius + 0.5 - dist).clamp(0.0, 1.0);
            if coverage > 0.0 {
                blend_pixel(surface, x, y, color, coverage);
            }
        }
    }
}

/// Fill an axis-aligned rectangle given two opposite corners.
pub fn fill_rect(surface: &mut Surface, ax: f32, ay: f32, bx: f32, by: f32, color: [f32; 4]) {
    let x0 = ax.min(bx).floor() as i32;
    let x1 = ax.max(bx).ceil() as i32;
    let y0 = ay.min(by).floor() as i32;
    let y1 = ay.max(by).ceil() as i32;
    for y in y0..y1 {
        for x in x0..x1 {
            blend_pixel(surface, x, y, color, 1.0);
        }
    }
}

/// Stroke a thick line segment by stamping discs along it. Used for freehand
/// path drawing so the stroke is continuous even with fast mouse moves.
pub fn stroke_segment(
    surface: &mut Surface,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    radius: f32,
    color: [f32; 4],
) {
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len = (dx * dx + dy * dy).sqrt();
    let steps = (len / (radius.max(0.5) * 0.5)).ceil().max(1.0) as i32;
    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        fill_circle(surface, x0 + dx * t, y0 + dy * t, radius, color);
    }
}
