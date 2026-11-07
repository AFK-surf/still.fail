use resvg::usvg::fontdb::Database;
use mbui_svg::render;

#[test]
fn external_images_are_not_read() {
    let file = format!("{}/tests/external.svg", env!("CARGO_MANIFEST_DIR"));
    assert!(std::path::Path::new(&file).is_file());
    let svg = format!(r#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="blue"/><image href="{}" width="10" height="10"/></svg>"#, file);
    let output = render(svg.as_bytes(), 10, &Database::new()).unwrap();
    assert!(output[8..].chunks_exact(4).all(|p| p == [0, 0, 255, 255]));
}

#[test]
fn embedded_images_remain_supported() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><image href="data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='10'%20height='10'%3E%3Crect%20width='10'%20height='10'%20fill='red'/%3E%3C/svg%3E" width="10" height="10"/></svg>"#;
    let output = render(svg, 10, &Database::new()).unwrap();
    assert!(output[8..].chunks_exact(4).all(|p| p == [255, 0, 0, 255]));
}
