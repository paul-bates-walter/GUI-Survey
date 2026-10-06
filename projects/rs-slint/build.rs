// Compile the Slint UI markup into generated Rust at build time.
fn main() {
    slint_build::compile("ui/app.slint").expect("compile ui/app.slint");
}
