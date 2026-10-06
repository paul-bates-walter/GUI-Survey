#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use iced::{Element, Task, Theme};

use png_editor_iced::{new_state, Message, State};


type UpdateFn = fn(&mut png_editor_iced::State, Message) -> Task<Message>;
type ViewFn = for<'a> fn(&'a State) -> Element<'a, Message>;
type TitleFn = fn(&State) -> String;


// WARNING: assumes single-thread
use std::cell::RefCell;
thread_local! {
    static HOT: RefCell<Hot> = RefCell::new(Hot::new());
}

struct Hot {
    source: Option<PathBuf>,
    libs: Vec<libloading::Library>,
    loaded_at: Option<SystemTime>,
    generation: u64,
    update: UpdateFn,
    view: ViewFn,
    title: TitleFn,
}

impl Hot {
    fn new() -> Self {
        let mut h = Hot {
            source: dylib_path().filter(|p| p.exists()),
            libs: Vec::new(),
            loaded_at: None,
            generation: 0,
            update: png_editor_iced::hot_update,
            view: png_editor_iced::hot_view,
            title: png_editor_iced::hot_title,
        };
        h.try_reload();
        h
    }

    fn reload_if_changed(&mut self) {
        let Some(src) = &self.source else { return };
        let Ok(mtime) = std::fs::metadata(src).and_then(|m| m.modified()) else {
            return;
        };
        if self.loaded_at != Some(mtime) {
            self.try_reload();
        }
    }

    fn try_reload(&mut self) {
        let Some(src) = self.source.clone() else { return };
        let Ok(mtime) = std::fs::metadata(&src).and_then(|m| m.modified()) else {
            return;
        };

        // Load a private copy so a concurrent `cargo build --lib` can overwrite
        // the original and so each dlopen sees a fresh path.
        self.generation += 1;
        let live = std::env::temp_dir().join(format!(
            "png-editor-iced-hot-{}-{}.so",
            std::process::id(),
            self.generation
        ));
        if std::fs::copy(&src, &live).is_err() {
            return;
        }

        match unsafe { load_symbols(&live) } {
            Ok((lib, update, view, title)) => {
                self.update = update;
                self.view = view;
                self.title = title;
                self.libs.push(lib); // retain (never unload) — see `libs` docs
                self.loaded_at = Some(mtime);
                let _ = std::fs::remove_file(&live);
                eprintln!("↻ hot-reloaded {}", src.display());
            }
            Err(e) => {
                let _ = std::fs::remove_file(&live);
                eprintln!("✗ hot reload failed ({e}); keeping running code");
            }
        }
    }
}

/// dlopen `path` and resolve the three app entry points. The returned function
/// pointers live inside `Library`, which must be kept alive while they are used.
unsafe fn load_symbols(
    path: &Path,
) -> Result<(libloading::Library, UpdateFn, ViewFn, TitleFn), libloading::Error> {
    let lib = libloading::Library::new(path)?;
    let update = *lib.get::<UpdateFn>(b"hot_update")?;
    let view = *lib.get::<ViewFn>(b"hot_view")?;
    let title = *lib.get::<TitleFn>(b"hot_title")?;
    Ok((lib, update, view, title))
}

fn dylib_path() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    let name = if cfg!(target_os = "windows") {
        "png_editor_iced.dll"
    } else if cfg!(target_os = "macos") {
        "libpng_editor_iced.dylib"
    } else {
        "libpng_editor_iced.so"
    };
    Some(dir.join(name))
}


// The dispatch functions reach the reloader through the thread-local, so they
// capture nothing and are trivially 'static for the iced runtime. They are plain
// `fn` items (not closures) so `view_dispatch` is inferred as the higher-ranked
// `for<'a> fn(&'a State) -> Element<'a, Message>` iced's View trait requires.

fn title_dispatch(state: &State) -> String {
    HOT.with(|h| (h.borrow().title)(state))
}

fn update_dispatch(state: &mut State, message: Message) -> Task<Message> {
    HOT.with(|h| {
        let mut h = h.borrow_mut();
        h.reload_if_changed(); // pick up a rebuilt dylib before handling input
        (h.update)(state, message)
    })
}

fn view_dispatch(state: &State) -> Element<'_, Message> {
    HOT.with(|h| (h.borrow().view)(state))
}

// A slow timer keeps the loop ticking so a rebuild is noticed (and redrawn) even
// when the user is idle; each Tick is a no-op in `update`.
fn tick_subscription(_state: &State) -> iced::Subscription<Message> {
    iced::time::every(Duration::from_millis(150)).map(|_| Message::Tick)
}

fn main() -> iced::Result {
    iced::application(title_dispatch, update_dispatch, view_dispatch)
        .subscription(tick_subscription)
        .theme(|_| Theme::Dark)
        .antialiasing(true)
        .run_with(|| (new_state(), Task::none()))
}
