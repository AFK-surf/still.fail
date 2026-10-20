///|
/// JPEGs scripts/web.sh puts next to the page (photos/0.jpg…).
fn picture(i : Int) -> String {
  "photos/\{i % 12}.jpg"
}
