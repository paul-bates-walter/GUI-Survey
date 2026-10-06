mod canvas;
mod pngio;
mod raster;

use std::fmt;
use std::path::PathBuf;

use iced::widget::{
    button, column, container, horizontal_space, image, pick_list, row, scrollable, slider, text,
    text_input, Stack,
};
use iced::{Color, ContentFit, Element, Length, Task};

use canvas::Editor;

const DEFAULT_WIDTH: u32 = 800;
const DEFAULT_HEIGHT: u32 = 600;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Circle,
    Rectangle,
    Path,
}

impl Mode {
    const ALL: [Mode; 3] = [Mode::Circle, Mode::Rectangle, Mode::Path];
}

impl fmt::Display for Mode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Mode::Circle => "Circle",
            Mode::Rectangle => "Rectangle",
            Mode::Path => "Path (freehand)",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pen {
    Black,
    White,
    Red,
    Green,
    Blue,
    Yellow,
    Cyan,
    Magenta,
}

impl Pen {
    const ALL: [Pen; 8] = [
        Pen::Black,
        Pen::White,
        Pen::Red,
        Pen::Green,
        Pen::Blue,
        Pen::Yellow,
        Pen::Cyan,
        Pen::Magenta,
    ];

    fn rgba(self) -> [f32; 4] {
        match self {
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

    fn color(self) -> Color {
        let [r, g, b, a] = self.rgba();
        Color::from_rgba(r, g, b, a)
    }
}

impl fmt::Display for Pen {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}

/// A committed drawing operation, in image-pixel coordinates.
#[derive(Debug, Clone, Copy)]
pub enum DrawOp {
    Circle { cx: f32, cy: f32, radius: f32 },
    Rect { ax: f32, ay: f32, bx: f32, by: f32 },
    Segment { x0: f32, y0: f32, x1: f32, y1: f32 },
}

/// The editor state. iced owns it; the field layout must stay identical across
/// a hot reload (adding/removing a field needs a restart). `repr(C)` pins the
/// field order so the host's and a rebuilt dylib's view of it agree.
#[repr(C)]
pub struct State {
    path: Option<PathBuf>,
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    handle: image::Handle,
    mode: Mode,
    pen: Pen,
    pen_radius: f32,
    metadata: Vec<(String, String)>,
    status: String,
    dirty: bool,
}

impl Default for State {
    fn default() -> Self {
        let (width, height) = (DEFAULT_WIDTH, DEFAULT_HEIGHT);
        let pixels = white_canvas(width, height);
        let handle = image::Handle::from_rgba(width, height, pixels.clone());
        State {
            path: None,
            width,
            height,
            pixels,
            handle,
            mode: Mode::Path,
            pen: Pen::Black,
            pen_radius: 6.0,
            metadata: vec![(String::new(), String::new())],
            status: "New 800×600 canvas".into(),
            dirty: false,
        }
    }
}

/// An opaque white RGBA8 buffer.
fn white_canvas(width: u32, height: u32) -> Vec<u8> {
    vec![255u8; (width as usize) * (height as usize) * 4]
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum Message {
    ModeSelected(Mode),
    PenSelected(Pen),
    PenRadiusChanged(f32),
    Commit(DrawOp),
    NewCanvas,
    ClearCanvas,
    OpenRequested,
    FileToOpen(Option<PathBuf>),
    SaveRequested,
    SaveAsRequested,
    FileToSave(Option<PathBuf>),
    MetaKeyChanged(usize, String),
    MetaValueChanged(usize, String),
    MetaAddRow,
    MetaRemoveRow(usize),
    /// Periodic no-op from the host's timer subscription. Its only job is to
    /// wake the loop so a freshly rebuilt dylib is picked up and redrawn even
    /// when the user is not interacting.
    Tick,
}

// ---------------------------------------------------------------------------
// Hot-reload entry points
// ---------------------------------------------------------------------------

/// Construct a fresh state. iced calls this (through the host) to boot.
pub fn new_state() -> State {
    State::default()
}

// These `#[no_mangle]` wrappers are what the host resolves out of the dylib each
// frame. They use the plain Rust ABI (not `extern "C"`), which is stable because
// the host and the dylib are always built by the same rustc from this same
// crate — the standard hot-reload arrangement.

#[no_mangle]
pub fn hot_update(state: &mut State, message: Message) -> Task<Message> {
    update(state, message)
}

#[no_mangle]
pub fn hot_view(state: &State) -> Element<'_, Message> {
    view(state)
}

#[no_mangle]
pub fn hot_title(state: &State) -> String {
    window_title(state)
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

fn refresh_handle(state: &mut State) {
    state.handle = image::Handle::from_rgba(state.width, state.height, state.pixels.clone());
}

fn apply_op(state: &mut State, op: DrawOp) {
    let mut surface = raster::Surface {
        width: state.width,
        height: state.height,
        rgba: &mut state.pixels,
    };
    let color = state.pen.rgba();
    match op {
        DrawOp::Circle { cx, cy, radius } => {
            raster::fill_circle(&mut surface, cx, cy, radius, color);
        }
        DrawOp::Rect { ax, ay, bx, by } => {
            raster::fill_rect(&mut surface, ax, ay, bx, by, color);
        }
        DrawOp::Segment { x0, y0, x1, y1 } => {
            raster::stroke_segment(&mut surface, x0, y0, x1, y1, state.pen_radius, color);
        }
    }
    refresh_handle(state);
    state.dirty = true;
}

fn write_to(state: &mut State, path: PathBuf) {
    match pngio::save(
        &path,
        state.width,
        state.height,
        &state.pixels,
        &state.metadata,
    ) {
        Ok(()) => {
            state.status = format!("Saved {}", path.display());
            state.path = Some(path);
            state.dirty = false;
        }
        Err(e) => state.status = format!("Save failed: {e}"),
    }
}

fn update(state: &mut State, message: Message) -> Task<Message> {
    match message {
        Message::Tick => {}
        Message::ModeSelected(mode) => state.mode = mode,
        Message::PenSelected(pen) => state.pen = pen,
        Message::PenRadiusChanged(r) => state.pen_radius = r,
        Message::Commit(op) => apply_op(state, op),

        Message::NewCanvas => {
            *state = State::default();
        }
        Message::ClearCanvas => {
            state.pixels = white_canvas(state.width, state.height);
            refresh_handle(state);
            state.dirty = true;
            state.status = "Canvas cleared".into();
        }

        Message::OpenRequested => {
            return Task::perform(
                async {
                    rfd::AsyncFileDialog::new()
                        .add_filter("PNG image", &["png"])
                        .pick_file()
                        .await
                        .map(|h| h.path().to_path_buf())
                },
                Message::FileToOpen,
            );
        }
        Message::FileToOpen(Some(path)) => match pngio::load(&path) {
            Ok(loaded) => {
                state.width = loaded.width;
                state.height = loaded.height;
                state.pixels = loaded.rgba;
                refresh_handle(state);
                state.metadata = if loaded.metadata.is_empty() {
                    vec![(String::new(), String::new())]
                } else {
                    loaded.metadata
                };
                state.status = format!("Opened {}", path.display());
                state.path = Some(path);
                state.dirty = false;
            }
            Err(e) => state.status = format!("Open failed: {e}"),
        },
        Message::FileToOpen(None) => {}

        Message::SaveRequested => match state.path.clone() {
            Some(path) => write_to(state, path),
            None => return Task::done(Message::SaveAsRequested),
        },
        Message::SaveAsRequested => {
            let suggested = state
                .path
                .as_ref()
                .and_then(|p| p.file_name())
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| "untitled.png".into());
            return Task::perform(
                async move {
                    rfd::AsyncFileDialog::new()
                        .add_filter("PNG image", &["png"])
                        .set_file_name(suggested)
                        .save_file()
                        .await
                        .map(|h| h.path().to_path_buf())
                },
                Message::FileToSave,
            );
        }
        Message::FileToSave(Some(path)) => write_to(state, path),
        Message::FileToSave(None) => {}

        Message::MetaKeyChanged(i, key) => {
            if let Some(entry) = state.metadata.get_mut(i) {
                entry.0 = key;
                state.dirty = true;
            }
        }
        Message::MetaValueChanged(i, value) => {
            if let Some(entry) = state.metadata.get_mut(i) {
                entry.1 = value;
                state.dirty = true;
            }
        }
        Message::MetaAddRow => state.metadata.push((String::new(), String::new())),
        Message::MetaRemoveRow(i) => {
            if i < state.metadata.len() {
                state.metadata.remove(i);
            }
            if state.metadata.is_empty() {
                state.metadata.push((String::new(), String::new()));
            }
            state.dirty = true;
        }
    }
    Task::none()
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

fn view(state: &State) -> Element<'_, Message> {
    let toolbar = row![
        button("New").on_press(Message::NewCanvas),
        button("Open").on_press(Message::OpenRequested),
        button("Save").on_press(Message::SaveRequested),
        button("Save As").on_press(Message::SaveAsRequested),
        button("Clear").on_press(Message::ClearCanvas),
        text("Mode:"),
        pick_list(Mode::ALL, Some(state.mode), Message::ModeSelected),
        text("Pen:"),
        pick_list(Pen::ALL, Some(state.pen), Message::PenSelected),
        text(format!("Size: {:.0}px", state.pen_radius)),
        slider(1.0..=64.0, state.pen_radius, Message::PenRadiusChanged).width(Length::Fixed(140.0)),
    ]
    .spacing(8)
    .align_y(iced::Alignment::Center);

    let editor = Editor {
        mode: state.mode,
        pen_color: state.pen.color(),
        pen_radius: state.pen_radius,
    };

    let surface = Stack::new()
        .push(
            image(state.handle.clone())
                .content_fit(ContentFit::None)
                .filter_method(image::FilterMethod::Nearest)
                .width(Length::Fixed(state.width as f32))
                .height(Length::Fixed(state.height as f32)),
        )
        .push(
            iced::widget::canvas(editor)
                .width(Length::Fixed(state.width as f32))
                .height(Length::Fixed(state.height as f32)),
        );

    let drawing_area = scrollable(container(surface).padding(8)).width(Length::FillPortion(3));

    let metadata_panel = scrollable(metadata_view(state))
        .width(Length::FillPortion(1))
        .height(Length::Fill);

    let body = row![drawing_area, metadata_panel].spacing(8);

    let status = text(state.status.as_str()).size(13);
    let title = row![
        text(current_title(state)).size(13),
        horizontal_space(),
        status
    ];

    column![toolbar, body, title]
        .spacing(8)
        .padding(10)
        .into()
}

fn metadata_view(state: &State) -> Element<'_, Message> {
    let header = row![
        text("PNG tEXt metadata").size(15),
        horizontal_space(),
        button("+ Add").on_press(Message::MetaAddRow),
    ]
    .align_y(iced::Alignment::Center);

    let mut rows = column![header].spacing(8);

    for (i, (key, value)) in state.metadata.iter().enumerate() {
        let entry = column![
            row![
                text_input("Keyword", key).on_input(move |s| Message::MetaKeyChanged(i, s)),
                button("✕").on_press(Message::MetaRemoveRow(i)),
            ]
            .spacing(4)
            .align_y(iced::Alignment::Center),
            text_input("Value", value).on_input(move |s| Message::MetaValueChanged(i, s)),
        ]
        .spacing(4);
        rows = rows.push(entry);
    }

    container(rows).padding(8).into()
}

fn current_title(state: &State) -> String {
    let name = state
        .path
        .as_ref()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "untitled.png".into());
    let mark = if state.dirty { "*" } else { "" };
    format!("{mark}{name}  —  {}×{}", state.width, state.height)
}

fn window_title(state: &State) -> String {
    format!("PNG Editor — iced  ·  {}", current_title(state))
}

#[cfg(test)]
mod hot_reload_tests {
    use super::*;

    fn painted_pixels(state: &State) -> usize {
        state
            .pixels
            .chunks_exact(4)
            .filter(|p| p[..3] != [255, 255, 255])
            .count()
    }

    fn dylib() -> Option<std::path::PathBuf> {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("target");
        for profile in ["debug", "release"] {
            let p = root.join(profile).join("libpng_editor_iced.so");
            if p.exists() {
                return Some(p);
            }
        }
        None
    }

    // Reloading the app dylib must not disturb the state iced holds. We drive the
    // update function *through the dylib* (the same call the host makes), reload
    // a second copy of the .so, and confirm the same State's pixels survive.
    #[test]
    fn reload_preserves_state() {
        let Some(path) = dylib() else {
            eprintln!("skip: dylib not built; run `cargo build` first");
            return;
        };
        type UpdateFn = fn(&mut State, Message) -> Task<Message>;
        type ViewFn = for<'a> fn(&'a State) -> Element<'a, Message>;

        let mut state = State::default();

        // Load the app dylib and drive the SAME state through it the way the host
        // does: run `update` (draws pixels) and build a `view` (headless
        // widget-tree construction — no GPU needed).
        let lib1 = unsafe { libloading::Library::new(&path) }.expect("load .so");
        let up1: libloading::Symbol<UpdateFn> = unsafe { lib1.get(b"hot_update") }.unwrap();
        let _ = up1(&mut state, Message::Commit(DrawOp::Circle { cx: 40.0, cy: 40.0, radius: 20.0 }));
        let after_first = painted_pixels(&state);
        assert!(after_first > 0, "drawing through the dylib must paint pixels");
        let vw1: libloading::Symbol<ViewFn> = unsafe { lib1.get(b"hot_view") }.unwrap();
        drop(vw1(&state));

        // Reload: load a second copy of the (possibly rebuilt) .so and keep
        // driving the same state through it. Like the host, we do NOT unload the
        // old library — objects it created may still be alive.
        let lib2 = unsafe { libloading::Library::new(&path) }.expect("reload .so");
        let up2: libloading::Symbol<UpdateFn> = unsafe { lib2.get(b"hot_update") }.unwrap();
        let _ = up2(&mut state, Message::Commit(DrawOp::Rect { ax: 0.0, ay: 0.0, bx: 5.0, by: 5.0 }));

        assert!(
            painted_pixels(&state) >= after_first,
            "state (and prior pixels) must survive the reload"
        );

        // Retain both libraries for the rest of the process, exactly as the host
        // does, so nothing that references their code is torn down under them.
        std::mem::forget(lib1);
        std::mem::forget(lib2);
    }
}
