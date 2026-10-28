// A film's Galaxy Z Fold in 3D, made here (no model of Samsung's: its shape as the phone has it, Z Fold7's sizes in
// centimetres): two halves on a hinge down the middle, the inner screen across both, the cover screen on the back of
// the left half; folded, the left half lies over the right one, its cover screen up; unfolding, it swings out toward
// the viewer to the left. Each screen shows what compose.html drew for it at that moment. window.frame3d({outer, inner,
// angle, cam}) draws one frame (compose3d.mjs films them), as duo3d/film.js does for the iPhone Duo.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const W = 1920, H = 1080;
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(40, W / H, .1, 250);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio || 1);
renderer.setSize(W, H);
renderer.setClearColor(0x000000, 0);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.1;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.getElementById('viewport').appendChild(renderer.domElement);
const environment = new RoomEnvironment();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(environment, .04).texture;
environment.dispose();
pmrem.dispose();
scene.environmentIntensity = 1.2;
scene.add(new THREE.HemisphereLight(0xffffff, 0xb5baa8, 1.6));
const key = new THREE.DirectionalLight(0xfffcf5, 2.4);
key.position.set(-15, 25, 30);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.radius = 8;
Object.assign(key.shadow.camera, { left: -14, right: 14, top: 12, bottom: -12, near: 1, far: 90 });
scene.add(key);
const rim = new THREE.DirectionalLight(0xe8edf5, 1.8);
rim.position.set(15, 5, -15);
scene.add(rim);
const ground = new THREE.Mesh(new THREE.PlaneGeometry(120, 120), new THREE.ShadowMaterial({ opacity: .16 }));
ground.position.z = -1.2;
ground.receiveShadow = true;
scene.add(ground);

// ---- the phone: Z Fold7's (unfolded 14.32 x 15.84, each half .42 thick; its cover screen 6.5" 21:9, its inner one
// 8" 1968 x 2184), its outer corners round, those on the hinge square
const HW = 7.16, HH = 15.84, T = .42;
const R = .66, RH = .06;
// what the screens leave round them: the cover screen's bezel, the inner one's
const BEZ = .2, IBEZ = .3;
const phone = new THREE.Group();
phone.position.y = -HH / 2;
scene.add(phone);

/** A rect x0..x1, y0..y1 with its corners each its own radius (left two `rl`, right two `rr`). */
function rounded(x0, y0, x1, y1, rl, rr) {
  const s = new THREE.Shape();
  s.moveTo(x0 + rl, y0);
  s.lineTo(x1 - rr, y0); s.quadraticCurveTo(x1, y0, x1, y0 + rr);
  s.lineTo(x1, y1 - rr); s.quadraticCurveTo(x1, y1, x1 - rr, y1);
  s.lineTo(x0 + rl, y1); s.quadraticCurveTo(x0, y1, x0, y1 - rl);
  s.lineTo(x0, y0 + rl); s.quadraticCurveTo(x0, y0, x0 + rl, y0);
  return s;
}
// its frame: brushed aluminium; its glass: black
const frame = new THREE.MeshPhysicalMaterial({ color: 0xb9bdc2, metalness: 1, roughness: .32, clearcoat: .3 });
const glass = new THREE.MeshPhysicalMaterial({ color: 0x0b0c0e, metalness: 0, roughness: .12, clearcoat: 1, clearcoatRoughness: .05 });
const backGlass = new THREE.MeshPhysicalMaterial({ color: 0x23262b, metalness: .2, roughness: .38, clearcoat: .6 });
/** A half's body, x0..x1 (its outer side round), its front at z = 0, its back at z = -T. */
function half(x0, x1, outerLeft) {
  const shape = rounded(x0, 0, x1, HH, outerLeft ? R : RH, outerLeft ? RH : R);
  const g = new THREE.ExtrudeGeometry(shape, { depth: T - .06, bevelEnabled: true, bevelThickness: .03, bevelSize: .03, bevelSegments: 4, curveSegments: 24 });
  g.translate(0, 0, -T + .03);
  const m = new THREE.Mesh(g, [glass, frame]);
  m.castShadow = true;
  return m;
}
/** A screen's surface, x0..x1, y0..y1, its corners `rl` and `rr`, its picture's u from u0 to u1 across it. */
function screenMesh(x0, y0, x1, y1, rl, rr, material, u0 = 0, u1 = 1) {
  const g = new THREE.ShapeGeometry(rounded(x0, y0, x1, y1, rl, rr), 24);
  const p = g.attributes.position;
  const uv = new Float32Array(p.count * 2);
  for (let i = 0; i < p.count; i++) {
    uv[i * 2] = u0 + (u1 - u0) * (p.getX(i) - x0) / (x1 - x0);
    uv[i * 2 + 1] = (p.getY(i) - y0) / (y1 - y0);
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  return new THREE.Mesh(g, material);
}

// the screens' pictures: canvases each frame's image is drawn into
const SIZES = { inner: [1968, 2184], outer: [1080, 2520] };
const screens = {};
for (const kind of ['inner', 'outer']) {
  const canvas = document.createElement('canvas');
  [canvas.width, canvas.height] = SIZES[kind];
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  screens[kind] = { canvas, texture, material: new THREE.MeshBasicMaterial({ map: texture, toneMapped: false }) };
}
// the inner screen's height, its width across both halves at its aspect (1968 x 2184)
const IH = HH - 2 * IBEZ, IW = IH * 1968 / 2184;
const ix0 = -IW / 2, ix1 = IW / 2, iy0 = IBEZ, iy1 = HH - IBEZ;
// the cover screen's, on the left half's back (as seen folded, its own left to right)
const OH = HH - 2 * BEZ - .1, OW = OH * 1080 / 2520;

// the right half: fixed, its front at z = T (the hinge's line, where the left half turns)
const right = half(0, HW, false);
right.position.z = T;
phone.add(right);
const innerR = screenMesh(0, iy0, ix1, iy1, 0, .45, screens.inner.material, .5, 1);
innerR.position.z = T + .004;
phone.add(innerR);
// the left half, on the hinge at x = 0, z = T: open, flat beside the right one; folded, over it, turned
const leaf = new THREE.Group();
leaf.position.set(0, 0, T);
phone.add(leaf);
const left = half(-HW, 0, true);
leaf.add(left);
const innerL = screenMesh(ix0, iy0, 0, iy1, .45, 0, screens.inner.material, 0, .5);
innerL.position.z = .004;
leaf.add(innerL);
// the crease: the fold's faint line down the inner screen
const crease = new THREE.Mesh(new THREE.PlaneGeometry(.05, IH), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: .04 }));
crease.position.set(0, HH / 2, T + .006);
phone.add(crease);
// the cover screen on the left half's back, turned to face out of it (seen right way round folded)
const cover = screenMesh(-OW / 2, -OH / 2, OW / 2, OH / 2, .55, .55, screens.outer.material);
cover.rotation.y = Math.PI;
cover.position.set(-HW / 2, HH / 2, -T - .004);
leaf.add(cover);
// its camera's hole, at the cover screen's top in its middle
const hole = new THREE.Mesh(new THREE.CircleGeometry(.11, 32), new THREE.MeshBasicMaterial({ color: 0x050506 }));
hole.rotation.y = Math.PI;
hole.position.set(-HW / 2, HH / 2 + OH / 2 - .32, -T - .006);
leaf.add(hole);
// the hinge's spine, along the fold's edge, seen while it is folded or turning
const spine = new THREE.Mesh(new THREE.CylinderGeometry(T, T, HH - .3, 32, 1, true, Math.PI, Math.PI), frame);
spine.position.set(0, HH / 2, T);
spine.castShadow = true;
phone.add(spine);
// the right half's back: its cameras, three in a column at its top by its outer edge (seen from the back only)
const bump = new THREE.Group();
for (let k = 0; k < 3; k++) {
  const ring = new THREE.Mesh(new THREE.CylinderGeometry(.42, .42, .12, 40), frame);
  ring.rotation.x = Math.PI / 2;
  ring.position.set(HW - 1.0, HH - 1.2 - k * 1.15, -T - .05);
  const lens = new THREE.Mesh(new THREE.CircleGeometry(.32, 32), glass);
  lens.rotation.y = Math.PI;
  lens.position.set(HW - 1.0, HH - 1.2 - k * 1.15, -T - .115);
  bump.add(ring, lens);
}
right.add(bump);

const images = {};
async function picture(url) {
  if (!url) return null;
  if (!images[url]) {
    const img = new Image();
    img.src = url;
    await img.decode();
    images[url] = img;
    const keys = Object.keys(images);
    if (keys.length > 6) delete images[keys[0]];
  }
  return images[url];
}
async function show(kind, url, shown) {
  const s = screens[kind];
  if (s.shown === url) return;
  s.shown = url;
  const c = s.canvas.getContext('2d');
  const img = await picture(url);
  c.fillStyle = '#000';
  c.fillRect(0, 0, s.canvas.width, s.canvas.height);
  if (img && shown) c.drawImage(img, 0, 0, s.canvas.width, s.canvas.height);
  s.texture.needsUpdate = true;
}

/**
 * One frame: `angle` how far it is open (0 folded, 180 flat), the screens' pictures, and the camera: looking at (x, y)
 * of the open phone (its units: the inner screen IW x IH about the middle; folded, the cover screen over the right
 * half) from `dist` away, turned `yaw` degrees about its upright axis and `pitch` about its sideways one.
 */
window.frame3d = async ({ outer, inner, angle, cam }) => {
  leaf.rotation.y = Math.PI * (1 - angle / 180);
  spine.visible = angle < 120;
  await show('outer', outer, angle < 180);
  await show('inner', inner, angle > 0);
  const [dist, x, y, yaw = 0, pitch = 0] = cam;
  const target = new THREE.Vector3(x, y, angle < 90 ? 2 * T : T);
  const dir = new THREE.Vector3(Math.sin(THREE.MathUtils.degToRad(yaw)) * Math.cos(THREE.MathUtils.degToRad(pitch)),
    Math.sin(THREE.MathUtils.degToRad(pitch)), Math.cos(THREE.MathUtils.degToRad(yaw)) * Math.cos(THREE.MathUtils.degToRad(pitch)));
  camera.position.copy(target).addScaledVector(dir, dist);
  camera.lookAt(target);
  renderer.render(scene, camera);
};
// (where a point of each screen is, in the phone's units, for the camera's script: zfold-en.cam3d.js)
window.ZFOLD = { HW, HH, IW, IH, OW, OH };
window.ready3d = true;
