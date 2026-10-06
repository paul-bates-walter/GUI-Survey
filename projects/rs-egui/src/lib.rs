//! Hot-reloadable app logic for the egui PNG editor.
//!
//! This crate is built as both an `rlib` (so the host binary knows `AppState`'s
//! layout and can construct it) and a `dylib` (so the running host can reload
//! the drawing / UI code in place — spec.md "Hot Swapping": genuine in-process
//! hot reload, the app keeps running with its state preserved).
//!
//! The design that makes this possible: egui is immediate-mode, so the whole UI
//! is rebuilt every frame from `AppState` by the free `draw` function. `AppState`
//! is a plain data record owned by the *host* (src/main.rs); each frame the host
//! calls this dylib's `hot_draw` through a raw pointer to that state. Rebuilding
//! the dylib (`cargo build --lib`, driven by scripts/watch.sh) swaps `draw` and
//! all its callees without touching the host's `AppState`, so pixels, tool, and
//! metadata survive the reload.

mod pngio;
mod raster;

use std::path::PathBuf;

use egui::{Color32, ColorImage, Pos2, Rect, Sense, Stroke, TextureHandle, TextureOptions};

const DEFAULT_WIDTH: u32 = 800;
const DEFAULT_HEIGHT: u32 = 600;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Circle,
    Rectangle,
    Path,
}

#[derive(Clone, Copy, PartialEq)]
enum Pen {
    Black,
    White,
    Red,
    Green,
    Blue,
    Yellow,
    Cyan,
    Magenta,
}

const PENS: [(Pen, &str); 8] = [
    (Pen::Black, "Black"),
    (Pen::White, "White"),
    (Pen::Red, "Red"),
    (Pen::Green, "Green"),
    (Pen::Blue, "Blue"),
    (Pen::Yellow, "Yellow"),
    (Pen::Cyan, "Cyan"),
    (Pen::Magenta, "Magenta"),
];

fn pen_rgba(p: Pen) -> [f32; 4] {
    match p {
        Pen::Black => [0.0, 0.0, 0.0, 1.0],
        Pen::White => [1.0, 1.0, 1.0, 1.0],
        Pen::Red => [0.90, 0.16, 0.16, 1.0],
        Pen::Green => [0.13, 0.70, 0.30, 1.0],
        Pen::Blue => [0.15, 0.39, 0.92, 1.0],
        Pen::Yellow => [0.98, 0.80, 0.08, 1.0],
        Pen::Cyan => [0.10, 0.75, 0.80, 1.0],
        Pen::Magenta => [0.83, 0.19, 0.71, 1.0],
    }
}

fn pen_color32(p: Pen) -> Color32 {
    let [r, g, b, a] = pen_rgba(p);
    Color32::from_rgba_unmultiplied(
        (r * 255.0) as u8,
        (g * 255.0) as u8,
        (b * 255.0) as u8,
        (a * 255.0) as u8,
    )
}

#[derive(Clone, Copy)]
enum Pending {
    Idle,
    Anchored(f32, f32),
}

/// The whole editor state. Owned by the host so it survives dylib reloads; its
/// field layout must stay identical across a reload (adding/removing a field
/// requires a full restart, the one limit of this hot-reload scheme). `repr(C)`
/// pins the field order so the host's view of the struct and a freshly rebuilt
/// dylib's view always agree.
#[repr(C)]
pub struct AppState {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    texture: Option<TextureHandle>,
    dirty: bool,
    mode: Mode,
    pen: Pen,
    pen_radius: f32,
    path: Option<PathBuf>,
    pending: Pending,
    last: Option<(f32, f32)>,
    metadata: Vec<(String, String)>,
    status: String,
}

impl Default for AppState {
    fn default() -> Self {
        AppState {
            width: DEFAULT_WIDTH,
            height: DEFAULT_HEIGHT,
            pixels: white_canvas(DEFAULT_WIDTH, DEFAULT_HEIGHT),
            texture: None,
            dirty: true,
            mode: Mode::Path,
            pen: Pen::Black,
            pen_radius: 6.0,
            path: None,
            pending: Pending::Idle,
            last: None,
            metadata: vec![(String::new(), String::new())],
            status: "New 800×600 canvas".into(),
        }
    }
}

/// Construct a fresh state. Called by the host (which links this crate as an
/// rlib) so the allocation lives in the host and outlives dylib reloads.
pub fn new_app_state() -> AppState {
    AppState::default()
}

// ---------------------------------------------------------------------------
// Hot-reload entry point
// ---------------------------------------------------------------------------

/// Stable C-ABI symbol the host resolves out of the dylib each frame. `st` and
/// `ctx` are borrowed for the duration of the call only.
///
/// # Safety
/// `st` must point at a live `AppState` created by `new_app_state` in a build
/// with an identical `AppState` layout; `ctx` must be a live `egui::Context`.
#[no_mangle]
pub unsafe extern "C" fn hot_draw(st: *mut AppState, ctx: *const egui::Context) {
    draw(&mut *st, &*ctx);
}

fn white_canvas(width: u32, height: u32) -> Vec<u8> {
    vec![255u8; (width as usize) * (height as usize) * 4]
}

fn dist(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = bx - ax;
    let dy = by - ay;
    (dx * dx + dy * dy).sqrt()
}

fn title_text(st: &AppState) -> String {
    let name = st
        .path
        .as_ref()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "untitled.png".into());
    format!("{name}  ({}×{})", st.width, st.height)
}

// ---------------------------------------------------------------------------
// Raster + IO helpers
// ---------------------------------------------------------------------------

/// Blend the committed shape between two points into the pixel buffer.
fn fill_shape(st: &mut AppState, ax: f32, ay: f32, bx: f32, by: f32) {
    let color = pen_rgba(st.pen);
    let mode = st.mode;
    let (w, h) = (st.width, st.height);
    let mut surface = raster::Surface {
        width: w,
        height: h,
        rgba: &mut st.pixels,
    };
    match mode {
        Mode::Circle => raster::fill_circle(&mut surface, ax, ay, dist(ax, ay, bx, by), color),
        Mode::Rectangle => raster::fill_rect(&mut surface, ax, ay, bx, by, color),
        Mode::Path => {}
    }
    st.dirty = true;
}

fn stroke_path(st: &mut AppState, x0: f32, y0: f32, x1: f32, y1: f32) {
    let color = pen_rgba(st.pen);
    let r = st.pen_radius;
    let (w, h) = (st.width, st.height);
    let mut surface = raster::Surface {
        width: w,
        height: h,
        rgba: &mut st.pixels,
    };
    raster::stroke_segment(&mut surface, x0, y0, x1, y1, r, color);
    st.dirty = true;
}

fn load_file(st: &mut AppState) {
    let Some(path) = rfd::FileDialog::new()
        .add_filter("PNG image", &["png"])
        .pick_file()
    else {
        return;
    };
    match pngio::load(&path) {
        Ok(loaded) => {
            st.width = loaded.width;
            st.height = loaded.height;
            st.pixels = loaded.rgba;
            st.metadata = if loaded.metadata.is_empty() {
                vec![(String::new(), String::new())]
            } else {
                loaded.metadata
            };
            st.status = format!("Opened {}", path.display());
            st.path = Some(path);
            st.dirty = true;
        }
        Err(e) => st.status = format!("Open failed: {e}"),
    }
}

fn save_file(st: &mut AppState, force_dialog: bool) {
    let path = if force_dialog || st.path.is_none() {
        rfd::FileDialog::new()
            .add_filter("PNG image", &["png"])
            .set_file_name("untitled.png")
            .save_file()
    } else {
        st.path.clone()
    };
    let Some(path) = path else { return };
    match pngio::save(&path, st.width, st.height, &st.pixels, &st.metadata) {
        Ok(()) => {
            st.status = format!("Saved {}", path.display());
            st.path = Some(path);
        }
        Err(e) => st.status = format!("Save failed: {e}"),
    }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

fn draw(st: &mut AppState, ctx: &egui::Context) {
    ctx.send_viewport_cmd(egui::ViewportCommand::Title(format!(
        "PNG Editor — egui  ·  {}",
        title_text(st)
    )));

    egui::TopBottomPanel::top("toolbar").show(ctx, |ui| toolbar(st, ui));
    egui::SidePanel::right("metadata")
        .default_width(300.0)
        .show(ctx, |ui| metadata_panel(st, ui));
    egui::TopBottomPanel::bottom("status").show(ctx, |ui| {
        ui.label(&st.status);
    });
    egui::CentralPanel::default().show(ctx, |ui| canvas(st, ui));
}

fn toolbar(st: &mut AppState, ui: &mut egui::Ui) {
    ui.horizontal_wrapped(|ui| {
        if ui.button("New").clicked() {
            *st = AppState::default();
        }
        if ui.button("Open").clicked() {
            load_file(st);
        }
        if ui.button("Save").clicked() {
            save_file(st, false);
        }
        if ui.button("Save As").clicked() {
            save_file(st, true);
        }
        if ui.button("Clear").clicked() {
            st.pixels = white_canvas(st.width, st.height);
            st.dirty = true;
            st.status = "Canvas cleared".into();
        }
        ui.separator();

        ui.label("Mode:");
        egui::ComboBox::from_id_salt("mode")
            .selected_text(match st.mode {
                Mode::Circle => "Circle",
                Mode::Rectangle => "Rectangle",
                Mode::Path => "Path (freehand)",
            })
            .show_ui(ui, |ui| {
                ui.selectable_value(&mut st.mode, Mode::Circle, "Circle");
                ui.selectable_value(&mut st.mode, Mode::Rectangle, "Rectangle");
                ui.selectable_value(&mut st.mode, Mode::Path, "Path (freehand)");
            });

        ui.label("Pen:");
        let pen_label = PENS
            .iter()
            .find(|(p, _)| *p == st.pen)
            .map(|(_, n)| *n)
            .unwrap_or("Black");
        egui::ComboBox::from_id_salt("pen")
            .selected_text(pen_label)
            .show_ui(ui, |ui| {
                for (pen, name) in PENS {
                    ui.selectable_value(&mut st.pen, pen, name);
                }
            });

        ui.add(egui::Slider::new(&mut st.pen_radius, 1.0..=64.0).text("Size"));
    });
}

fn metadata_panel(st: &mut AppState, ui: &mut egui::Ui) {
    ui.horizontal(|ui| {
        ui.heading("PNG tEXt metadata");
        if ui.button("+ Add").clicked() {
            st.metadata.push((String::new(), String::new()));
        }
    });
    ui.separator();

    let mut remove: Option<usize> = None;
    egui::ScrollArea::vertical().show(ui, |ui| {
        for i in 0..st.metadata.len() {
            ui.horizontal(|ui| {
                ui.add(
                    egui::TextEdit::singleline(&mut st.metadata[i].0)
                        .hint_text("Keyword")
                        .desired_width(f32::INFINITY),
                );
                if ui.button("✕").clicked() {
                    remove = Some(i);
                }
            });
            ui.add(
                egui::TextEdit::singleline(&mut st.metadata[i].1)
                    .hint_text("Value")
                    .desired_width(f32::INFINITY),
            );
            ui.add_space(6.0);
        }
    });

    if let Some(i) = remove {
        st.metadata.remove(i);
        if st.metadata.is_empty() {
            st.metadata.push((String::new(), String::new()));
        }
    }
}

#[cfg(test)]
fn painted_pixels(st: &AppState) -> usize {
    st.pixels.chunks_exact(4).filter(|p| p[..3] != [255, 255, 255]).count()
}

fn canvas(st: &mut AppState, ui: &mut egui::Ui) {
    egui::ScrollArea::both().show(ui, |ui| {
        let size = egui::vec2(st.width as f32, st.height as f32);
        let (response, painter) = ui.allocate_painter(size, Sense::click_and_drag());
        let rect = response.rect;
        let origin = rect.min;
        let to_img = |p: Pos2| (p.x - origin.x, p.y - origin.y);

        // --- Input -------------------------------------------------------
        match st.mode {
            Mode::Path => {
                if response.drag_started() {
                    st.last = response.interact_pointer_pos().map(to_img);
                }
                if response.dragged() {
                    if let (Some(p), Some((lx, ly))) = (response.interact_pointer_pos(), st.last) {
                        let (x, y) = to_img(p);
                        stroke_path(st, lx, ly, x, y);
                        st.last = Some((x, y));
                    }
                }
                if response.drag_stopped() {
                    st.last = None;
                }
            }
            _ => {
                if response.clicked() {
                    if let Some(p) = response.interact_pointer_pos() {
                        let (x, y) = to_img(p);
                        match st.pending {
                            Pending::Anchored(ax, ay) => {
                                fill_shape(st, ax, ay, x, y);
                                st.pending = Pending::Idle;
                            }
                            Pending::Idle => st.pending = Pending::Anchored(x, y),
                        }
                    }
                }
            }
        }

        // --- Upload texture if pixels changed ----------------------------
        if st.dirty || st.texture.is_none() {
            let image = ColorImage::from_rgba_unmultiplied(
                [st.width as usize, st.height as usize],
                &st.pixels,
            );
            match &mut st.texture {
                Some(t) => t.set(image, TextureOptions::NEAREST),
                None => {
                    st.texture =
                        Some(ui.ctx().load_texture("canvas", image, TextureOptions::NEAREST))
                }
            }
            st.dirty = false;
        }

        // --- Paint image + preview ---------------------------------------
        if let Some(tex) = &st.texture {
            painter.image(
                tex.id(),
                rect,
                Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                Color32::WHITE,
            );
        }

        if let Pending::Anchored(ax, ay) = st.pending {
            if let Some(cur) = response.hover_pos() {
                let stroke = Stroke::new(st.pen_radius.max(1.0), pen_color32(st.pen));
                let anchor = egui::pos2(origin.x + ax, origin.y + ay);
                match st.mode {
                    Mode::Circle => {
                        painter.circle_stroke(
                            anchor,
                            dist(anchor.x, anchor.y, cur.x, cur.y),
                            stroke,
                        );
                    }
                    Mode::Rectangle => {
                        painter.rect_stroke(
                            Rect::from_two_pos(anchor, cur),
                            egui::Rounding::ZERO,
                            stroke,
                        );
                    }
                    Mode::Path => {}
                }
            }
        }
    });
}

// ---------------------------------------------------------------------------
// Hot-reload regression test (spec.md "Hot Swapping")
// ---------------------------------------------------------------------------
#[cfg(test)]
mod hot_reload_tests {
    use super::*;

    // Locate the app dylib cargo builds alongside this crate. Returns None if it
    // has not been built yet (`cargo build`), so the test skips rather than fails.
    fn dylib() -> Option<std::path::PathBuf> {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("target");
        for profile in ["debug", "release"] {
            let p = root.join(profile).join("libpng_editor_egui.so");
            if p.exists() {
                return Some(p);
            }
        }
        None
    }

    // Run one real egui frame that calls the dylib's `hot_draw` on `st`. No GPU
    // or display is needed — this exercises the exact cross-dylib call the host
    // makes each frame (host-owned Context + AppState, egui code living in the
    // .so), which is the delicate part of in-process hot reload.
    unsafe fn frame_via(lib: &libloading::Library, st: &mut AppState) {
        let hot: libloading::Symbol<unsafe extern "C" fn(*mut AppState, *const egui::Context)> =
            lib.get(b"hot_draw").expect("hot_draw symbol");
        let ctx = egui::Context::default();
        let _ = ctx.run(egui::RawInput::default(), |ctx| {
            hot(st as *mut AppState, ctx as *const egui::Context)
        });
    }

    #[test]
    fn reload_preserves_state_and_runs_dylib_code() {
        let Some(path) = dylib() else {
            eprintln!("skip: dylib not built; run `cargo build` first");
            return;
        };

        // State lives here (the host role). Draw into it so there is something
        // to preserve across a reload.
        let mut st = AppState::default();
        stroke_path(&mut st, 4.0, 4.0, 40.0, 30.0);
        fill_shape_circle(&mut st, 20.0, 20.0, 10.0);
        let before = painted_pixels(&st);
        assert!(before > 0, "expected drawn pixels before reload");

        // Load the dylib and render a frame through it (proves the .so's egui
        // code runs against the host's Context without crashing).
        let lib1 = unsafe { libloading::Library::new(&path) }.expect("load .so");
        unsafe { frame_via(&lib1, &mut st) };
        assert_eq!(painted_pixels(&st), before, "frame must not alter pixels");

        // Simulate a hot reload: load a second copy of the (possibly just-rebuilt)
        // library and render again through the NEW handle on the SAME state. Like
        // the host, we do NOT unload the old library — egui state (a TextureHandle
        // in AppState) built through it may still be alive.
        let lib2 = unsafe { libloading::Library::new(&path) }.expect("reload .so");
        unsafe { frame_via(&lib2, &mut st) };
        unsafe { frame_via(&lib2, &mut st) };

        // The state object was never rebuilt — its pixels survive the swap.
        assert_eq!(
            painted_pixels(&st),
            before,
            "AppState (and its pixels) must survive the reload"
        );

        // Retain both libraries for the rest of the process, as the host does.
        std::mem::forget(lib1);
        std::mem::forget(lib2);
    }

    // Small helper so the test can commit a circle without going through a UI
    // event; mirrors what fill_shape does in Circle mode.
    fn fill_shape_circle(st: &mut AppState, cx: f32, cy: f32, r: f32) {
        st.mode = Mode::Circle;
        fill_shape(st, cx, cy, cx + r, cy);
    }
}
