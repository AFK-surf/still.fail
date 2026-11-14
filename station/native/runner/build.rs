//! Links libghostty-vt (src/ghostty.rs) where the runner keeps terminals, on macOS and Linux: the static library
//! scripts/native.ts prebuilds (`ghostty-vt`), from GHOSTTY_VT_DIR (its part's directory, which native.ts gives the
//! runner's build), else asked of native.ts here (a `cargo test` in the checkout).

use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_DIR");
    let target = std::env::var("TARGET").unwrap();
    let part = match target.as_str() {
        "aarch64-apple-darwin" => "darwin-arm64",
        "x86_64-unknown-linux-gnu" => "linux-x64",
        "aarch64-unknown-linux-gnu" => "linux-arm64",
        // Windows' terminals are not kept yet (ConPTY): nothing to link.
        _ => return,
    };
    let dir = match std::env::var_os("GHOSTTY_VT_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => {
            let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../..");
            let out = Command::new("node").current_dir(&root).args(["scripts/native.ts", "path", "ghostty-vt", part]).output().expect("node scripts/native.ts path ghostty-vt");
            assert!(out.status.success(), "native.ts path ghostty-vt {part}: {}", String::from_utf8_lossy(&out.stderr));
            PathBuf::from(String::from_utf8(out.stdout).unwrap().trim())
        }
    };
    // Copied under the name the linker looks for whatever the target (`-l static=ghostty_vt`).
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    std::fs::copy(dir.join("lib/libghostty-vt.a"), out.join("libghostty_vt.a")).expect("libghostty-vt.a");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=ghostty_vt");
}
