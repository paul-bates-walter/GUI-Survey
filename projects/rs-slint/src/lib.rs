//! Hot-reloadable app logic for the Slint PNG editor.
//!
//! Built as an rlib (so the host binary knows the generated `AppWindow`/`MetaRow`
//! types and the plain `AppState`) and a dylib (so the running host can reload
//! the callback logic in place — spec.md "Hot Swapping": genuine in-process hot
//! reload, not a rebuild-and-restart).
//!
//! Slint owns the window and the event loop. The reloadable surface is
//! `install`: it (re)wires every UI callback and pushes the current state into
//! the window. The host (src/main.rs) creates the `AppWindow` + `AppState`, calls
//! the dylib's `hot_install` once at startup, and calls it again whenever
//! scripts/watch.sh rebuilds the dylib — each reload replaces the callback
//! closures on the live window with the new code. All of Slint's own state (the
//! window, the models) is host-owned and passed in by reference, so the picture
//! and the metadata form survive the swap.

// Hide the console window on Windows in release builds.
#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

mod pngio;
mod raster;

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use slint::{ComponentHandle, Image, Rgba8Pixel, SharedPixelBuffer, VecModel};

slint::include_modules!();

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

fn mode_from_index(i: i32) -> Mode {
    match i {
        0 => Mode::Circle,
        1 => Mode::Rectangle,
        _ => Mode::Path,
    }
}

fn mode_index(m: Mode) -> i32 {
    match m {
        Mode::Circle => 0,
        Mode::Rectangle => 1,
        Mode::Path => 2,
    }
}

#[derive(Clone, Copy)]
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

fn pen_from_index(i: i32) -> Pen {
    match i {
        0 => Pen::Black,
        1 => Pen::White,
        2 => Pen::Red,
        3 => Pen::Green,
        4 => Pen::Blue,
        5 => Pen::Yellow,
        6 => Pen::Cyan,
        _ => Pen::Magenta,
    }
}

fn pen_index(p: Pen) -> i32 {
    match p {
        Pen::Black => 0,
        Pen::White => 1,
        Pen::Red => 2,
        Pen::Green => 3,
        Pen::Blue => 4,
        Pen::Yellow => 5,
        Pen::Cyan => 6,
        Pen::Magenta => 7,
    }
}

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

#[derive(Clone, Copy)]
enum Pending {
    Idle,
    Anchored(f32, f32),
    Drawing(f32, f32),
}

/// Plain editor state, owned by the host behind Rc<RefCell<>>. Toolkit-free, so
/// it is untouched by a dylib reload. (Adding/removing a field changes its
/// layout and needs a restart — the one limit of the hot-reload scheme.)
#[repr(C)]
pub struct AppState {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    mode: Mode,
    pen: Pen,
    pen_radius: f32,
    path: Option<PathBuf>,
    pending: Pending,
    metadata: Vec<(String, String)>,
}

impl Default for AppState {
    fn default() -> Self {
        AppState {
            width: DEFAULT_WIDTH,
            height: DEFAULT_HEIGHT,
            pixels: white_canvas(DEFAULT_WIDTH, DEFAULT_HEIGHT),
            mode: Mode::Path,
            pen: Pen::Black,
            pen_radius: 6.0,
            path: None,
            pending: Pending::Idle,
            metadata: vec![(String::new(), String::new())],
        }
    }
}

fn white_canvas(width: u32, height: u32) -> Vec<u8> {
    vec![255u8; (width as usize) * (height as usize) * 4]
}

fn dist(ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = bx - ax;
    let dy = by - ay;
    (dx * dx + dy * dy).sqrt()
}

// ---------------------------------------------------------------------------
// Hot-reload entry points
// ---------------------------------------------------------------------------

/// Fresh state, allocated in (and owned by) the host so it survives reloads.
pub fn new_state() -> Rc<RefCell<AppState>> {
    Rc::new(RefCell::new(AppState::default()))
}

/// The metadata list model, host-owned for the same reason.
pub fn new_model() -> Rc<VecModel<MetaRow>> {
    Rc::new(VecModel::<MetaRow>::default())
}

/// Wire every UI callback and push the current state into the window. Called at
/// startup and again after each reload; Slint's `on_*` setters replace the
/// previous handler, so re-calling this swaps in the freshly built code.
///
/// Plain Rust ABI (see host): host and dylib are built by the same rustc.
#[no_mangle]
pub fn hot_install(
    ui: &AppWindow,
    state: &Rc<RefCell<AppState>>,
    model: &Rc<VecModel<MetaRow>>,
) {
    install(ui, state, model)
}

// ---------------------------------------------------------------------------
// View helpers
// ---------------------------------------------------------------------------

fn to_image(width: u32, height: u32, rgba: &[u8]) -> Image {
    let mut buffer = SharedPixelBuffer::<Rgba8Pixel>::new(width, height);
    buffer.make_mut_bytes().copy_from_slice(rgba);
    Image::from_rgba8(buffer)
}

fn title_text(st: &AppState) -> String {
    let name = st
        .path
        .as_ref()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "untitled.png".into());
    format!("PNG Editor — slint  ·  {name}  ({}×{})", st.width, st.height)
}

fn build_rows(meta: &[(String, String)]) -> Vec<MetaRow> {
    meta.iter()
        .map(|(k, v)| MetaRow {
            key: k.as_str().into(),
            value: v.as_str().into(),
        })
        .collect()
}

fn refresh(ui: &AppWindow, st: &AppState) {
    ui.set_image(to_image(st.width, st.height, &st.pixels));
    ui.set_img_width(st.width as i32);
    ui.set_img_height(st.height as i32);
    ui.set_title_text(title_text(st).into());
}

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
}

fn write_png(ui: &AppWindow, st: &mut AppState, path: PathBuf) {
    match pngio::save(&path, st.width, st.height, &st.pixels, &st.metadata) {
        Ok(()) => {
            st.path = Some(path.clone());
            ui.set_title_text(title_text(st).into());
            ui.set_status_text(format!("Saved {}", path.display()).into());
        }
        Err(e) => ui.set_status_text(format!("Save failed: {e}").into()),
    }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

fn install(ui: &AppWindow, state: &Rc<RefCell<AppState>>, model: &Rc<VecModel<MetaRow>>) {
    // Push current state into the window (also re-run on reload so the UI stays
    // in sync with the code that just replaced it).
    {
        let st = state.borrow();
        model.set_vec(build_rows(&st.metadata));
        ui.set_metadata(model.clone().into());
        ui.set_pen_radius(st.pen_radius);
        ui.set_mode_index(mode_index(st.mode));
        ui.set_pen_index(pen_index(st.pen));
        refresh(ui, &st);
        ui.set_status_text("New 800×600 canvas".into());
    }

    let weak = ui.as_weak();

    // --- Drawing input ----------------------------------------------------
    {
        let (st, w) = (state.clone(), weak.clone());
        ui.on_pointer_down(move |x, y| {
            let ui = w.unwrap();
            let mut st = st.borrow_mut();
            match st.mode {
                Mode::Path => st.pending = Pending::Drawing(x, y),
                _ => match st.pending {
                    Pending::Anchored(ax, ay) => {
                        fill_shape(&mut st, ax, ay, x, y);
                        st.pending = Pending::Idle;
                        refresh(&ui, &st);
                    }
                    _ => st.pending = Pending::Anchored(x, y),
                },
            }
        });
    }
    {
        let (st, w) = (state.clone(), weak.clone());
        ui.on_pointer_move(move |x, y| {
            let ui = w.unwrap();
            let mut st = st.borrow_mut();
            match st.pending {
                Pending::Drawing(px, py) => {
                    let color = pen_rgba(st.pen);
                    let r = st.pen_radius;
                    let (bw, bh) = (st.width, st.height);
                    {
                        let mut s = raster::Surface {
                            width: bw,
                            height: bh,
                            rgba: &mut st.pixels,
                        };
                        raster::stroke_segment(&mut s, px, py, x, y, r, color);
                    }
                    st.pending = Pending::Drawing(x, y);
                    ui.set_image(to_image(st.width, st.height, &st.pixels));
                }
                Pending::Anchored(ax, ay) => {
                    let mut preview = st.pixels.clone();
                    let color = pen_rgba(st.pen);
                    let mode = st.mode;
                    let (bw, bh) = (st.width, st.height);
                    {
                        let mut s = raster::Surface {
                            width: bw,
                            height: bh,
                            rgba: &mut preview,
                        };
                        match mode {
                            Mode::Circle => {
                                raster::fill_circle(&mut s, ax, ay, dist(ax, ay, x, y), color)
                            }
                            Mode::Rectangle => raster::fill_rect(&mut s, ax, ay, x, y, color),
                            Mode::Path => {}
                        }
                    }
                    ui.set_image(to_image(bw, bh, &preview));
                }
                Pending::Idle => {}
            }
        });
    }
    {
        let st = state.clone();
        ui.on_pointer_up(move |_x, _y| {
            let mut st = st.borrow_mut();
            if let Pending::Drawing(_, _) = st.pending {
                st.pending = Pending::Idle;
            }
        });
    }

    // --- Tool settings ----------------------------------------------------
    {
        let st = state.clone();
        ui.on_mode_changed(move |i| state_set(&st, |s| s.mode = mode_from_index(i)));
    }
    {
        let st = state.clone();
        ui.on_pen_changed(move |i| state_set(&st, |s| s.pen = pen_from_index(i)));
    }
    {
        let st = state.clone();
        ui.on_radius_changed(move |v| state_set(&st, |s| s.pen_radius = v));
    }

    // --- Canvas lifecycle -------------------------------------------------
    {
        let (st, w, m) = (state.clone(), weak.clone(), model.clone());
        ui.on_new_canvas(move || {
            let ui = w.unwrap();
            let mut st = st.borrow_mut();
            *st = AppState::default();
            m.set_vec(build_rows(&st.metadata));
            ui.set_pen_radius(st.pen_radius);
            ui.set_mode_index(mode_index(st.mode));
            ui.set_pen_index(pen_index(st.pen));
            refresh(&ui, &st);
            ui.set_status_text("New 800×600 canvas".into());
        });
    }
    {
        let (st, w) = (state.clone(), weak.clone());
        ui.on_clear_canvas(move || {
            let ui = w.unwrap();
            let mut st = st.borrow_mut();
            st.pixels = white_canvas(st.width, st.height);
            refresh(&ui, &st);
            ui.set_status_text("Canvas cleared".into());
        });
    }

    // --- Filesystem -------------------------------------------------------
    {
        let (st, w, m) = (state.clone(), weak.clone(), model.clone());
        ui.on_open_file(move || {
            let ui = w.unwrap();
            let Some(path) = rfd::FileDialog::new()
                .add_filter("PNG image", &["png"])
                .pick_file()
            else {
                return;
            };
            let mut st = st.borrow_mut();
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
                    st.path = Some(path.clone());
                    m.set_vec(build_rows(&st.metadata));
                    refresh(&ui, &st);
                    ui.set_status_text(format!("Opened {}", path.display()).into());
                }
                Err(e) => ui.set_status_text(format!("Open failed: {e}").into()),
            }
        });
    }
    {
        let (st, w) = (state.clone(), weak.clone());
        ui.on_save_file(move || {
            let ui = w.unwrap();
            let existing = st.borrow().path.clone();
            let path = existing.or_else(|| {
                rfd::FileDialog::new()
                    .add_filter("PNG image", &["png"])
                    .set_file_name("untitled.png")
                    .save_file()
            });
            if let Some(path) = path {
                write_png(&ui, &mut st.borrow_mut(), path);
            }
        });
    }
    {
        let (st, w) = (state.clone(), weak.clone());
        ui.on_save_as_file(move || {
            let ui = w.unwrap();
            let path = rfd::FileDialog::new()
                .add_filter("PNG image", &["png"])
                .set_file_name("untitled.png")
                .save_file();
            if let Some(path) = path {
                write_png(&ui, &mut st.borrow_mut(), path);
            }
        });
    }

    // --- Metadata form ----------------------------------------------------
    {
        let st = state.clone();
        ui.on_meta_key_changed(move |idx, text| {
            state_set(&st, |s| {
                if let Some(entry) = s.metadata.get_mut(idx as usize) {
                    entry.0 = text.to_string();
                }
            });
        });
    }
    {
        let st = state.clone();
        ui.on_meta_value_changed(move |idx, text| {
            state_set(&st, |s| {
                if let Some(entry) = s.metadata.get_mut(idx as usize) {
                    entry.1 = text.to_string();
                }
            });
        });
    }
    {
        let (st, m) = (state.clone(), model.clone());
        ui.on_meta_add(move || {
            let mut st = st.borrow_mut();
            st.metadata.push((String::new(), String::new()));
            m.set_vec(build_rows(&st.metadata));
        });
    }
    {
        let (st, m) = (state.clone(), model.clone());
        ui.on_meta_remove(move |idx| {
            let mut st = st.borrow_mut();
            let i = idx as usize;
            if i < st.metadata.len() {
                st.metadata.remove(i);
            }
            if st.metadata.is_empty() {
                st.metadata.push((String::new(), String::new()));
            }
            m.set_vec(build_rows(&st.metadata));
        });
    }
}

/// Borrow the state mutably and apply a change. Keeps the callback closures terse.
fn state_set(state: &Rc<RefCell<AppState>>, f: impl FnOnce(&mut AppState)) {
    f(&mut state.borrow_mut());
}
