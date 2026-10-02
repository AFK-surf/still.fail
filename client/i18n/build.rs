// Every catalog file, included: catalog/<lang>/<part>.json, whatever parts there are.
use std::{env, fs, path::Path};

fn main() {
    // The catalog goes into the build as text: a cached build must not keep words from before they changed.
    println!("cargo:rerun-if-changed=build.rs");
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("catalog");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut entries = Vec::new();
    for lang in ["zh", "en"] {
        let dir = root.join(lang);
        println!("cargo:rerun-if-changed={}", dir.display());
        let mut files: Vec<_> = fs::read_dir(&dir).map(|d| d.filter_map(|e| e.ok()).map(|e| e.path()).collect()).unwrap_or_default();
        files.sort();
        for file in files.into_iter().filter(|f| f.extension().is_some_and(|e| e == "json")) {
            println!("cargo:rerun-if-changed={}", file.display());
            entries.push(format!("(\"{lang}\", include_str!({:?})),", file.display().to_string()));
        }
    }
    let out = Path::new(&env::var("OUT_DIR").unwrap()).join("catalog.rs");
    fs::write(out, format!("const FILES: &[(&str, &str)] = &[\n{}\n];\n", entries.join("\n"))).unwrap();
}
