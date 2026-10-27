// A film's iPhone Duo in 3D: Apple's own model (its AR USDZ, prepare-assets.py) folded and unfolded as iOS does it,
// the screens' pictures projected and blurred as github.com/chuspeeism/iphone-duo does (MIT, LICENSE-iphone-duo: its
// main.js, the fold, the projection and the blur kept as it has them), each screen showing what compose.html drew for
// it at that moment. window.frame3d({outer, inner, angle, cam}) draws one frame: compose.mjs films them.
import * as THREE from 'three';
import { USDLoader } from 'three/addons/loaders/USDLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const W = 1920, H = 1080;
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(40, W / H, .1, 250);
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.setClearColor(0x000000, 0);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.18;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.getElementById('viewport').appendChild(renderer.domElement);
const environment = new RoomEnvironment();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(environment, .04).texture;
environment.dispose();
pmrem.dispose();
scene.environmentIntensity = 1.35;
scene.add(new THREE.HemisphereLight(0xffffff, 0xb5baa8, 1.8));
const key = new THREE.DirectionalLight(0xfffcf5, 2.6);
key.position.set(-15, 25, 30);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.radius = 8;
Object.assign(key.shadow.camera, { left: -14, right: 14, top: 12, bottom: -12, near: 1, far: 90 });
scene.add(key);
const rim = new THREE.DirectionalLight(0xe8edf5, 2);
rim.position.set(15, 5, -15);
scene.add(rim);
// what it lies on: only its shadow shows, on the page's ground
const ground = new THREE.Mesh(new THREE.PlaneGeometry(120, 120), new THREE.ShadowMaterial({ opacity: .16 }));
ground.position.z = -1.2;
ground.receiveShadow = true;
scene.add(ground);
const phone = new THREE.Group();
scene.add(phone);
const bend = { value: 0 };
const screens = {};
const uiReferenceEye = new THREE.Vector3(0, 0, 40);
const innerUIFrame = new THREE.Vector4(-7.89935, .34562 - 5.8974, 15.7987, 11.1035);
const outerUIFrame = new THREE.Vector4(.23396, .27173 - 5.8974, 7.73936, 11.2513)
  .multiplyScalar((uiReferenceEye.z - .24948) / (uiReferenceEye.z - .825538));
// the screens' pictures: canvases each frame's image is drawn into, at twice the reference's size (its blur, 72 of
// its pixels, kept the same on the screen: uiBlur)
const SIZES = { inner: [3200, 2250], outer: [1548, 2250] };
for (const kind of ['inner', 'outer']) {
  const canvas = document.createElement('canvas');
  [canvas.width, canvas.height] = SIZES[kind];
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const material = new THREE.MeshBasicMaterial({ map: texture, toneMapped: false });
  screens[kind] = {
    canvas, texture, material,
    frame: { value: (kind === 'inner' ? innerUIFrame : outerUIFrame).clone() },
    gradient: { value: new THREE.Vector2(kind === 'inner' ? .5 : 0, kind === 'inner' ? 0 : 1) },
    pixel: { value: new THREE.Vector2(1 / canvas.width, 1 / canvas.height) },
    blur: { value: 72 * canvas.height / 1125 },
  };
}

const screenShader = `
uniform float foldAngle;
uniform vec2 uiPixel;
uniform vec4 uiFrame;
uniform vec2 uiGradient;
uniform vec3 uiReferenceEye;
uniform float uiBlur;
varying vec3 vUIPosition;
vec3 screenColor() {
  // Intersect the fixed front-view ray with the unfolded inner-screen plane.
  float depth = (0.24948 - uiReferenceEye.z) / (vUIPosition.z - uiReferenceEye.z);
  vec2 projected = uiReferenceEye.xy + (vUIPosition.xy - uiReferenceEye.xy) * depth;
  vec2 sourceUV = (projected - uiFrame.xy) / uiFrame.zw;
  #ifdef INNER_UI
    float progress = clamp(foldAngle / 1.570796327, 0.0, 1.0);
  #else
    // Anchor the image to the projected hinge-side edge of the outer screen.
    float c = cos(foldAngle), s = sin(foldAngle);
    vec2 hingeEdge = vec2(-0.23396, -0.27463 - 0.275454);
    vec2 foldedEdge = vec2(c * hingeEdge.x + s * hingeEdge.y,
      -s * hingeEdge.x + c * hingeEdge.y + 0.275454);
    float edgeDepth = (0.24948 - uiReferenceEye.z) / (foldedEdge.y - uiReferenceEye.z);
    float anchorX = uiReferenceEye.x + (foldedEdge.x - uiReferenceEye.x) * edgeDepth;
    sourceUV.x = uiGradient.x + (projected.x - anchorX) / uiFrame.z;
    float progress = clamp((3.141592654 - foldAngle) / 1.570796327, 0.0, 1.0);
  #endif
  float edge = (sourceUV.x - uiGradient.x) / (uiGradient.y - uiGradient.x);
  float motion = smoothstep(0.0, 1.0, progress);
  float blurGradient = clamp(edge, 0.0, 1.0);
  float darkenGradient = clamp((edge - 0.2) / 0.8, 0.0, 1.0);
  float effect = motion * pow(darkenGradient, 1.35);
  float radius = uiBlur * motion * pow(blurGradient, 1.35);
  vec2 aa = max(fwidth(sourceUV), uiPixel * 0.5);
  vec2 dx = dFdx(sourceUV) / uiPixel;
  vec2 dy = dFdy(sourceUV) / uiPixel;
  float baseLod = log2(max(1.0, max(length(dx), length(dy))));
  vec2 coverage = smoothstep(-aa, aa, sourceUV)
    * (1.0 - smoothstep(vec2(1.0) - aa, vec2(1.0) + aa, sourceUV));
  vec3 color = textureLod(map, clamp(sourceUV, vec2(0.0), vec2(1.0)), baseLod).rgb * coverage.x * coverage.y;
  if (radius > 0.0) {
    float lod = max(baseLod, log2(max(1.0, radius)));
    vec2 footprint = max(aa, uiPixel * radius * 0.75);
    color = vec3(0.0);
    for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
        float wx = x == 0 ? 6.0 : (abs(x) == 1 ? 4.0 : 1.0);
        float wy = y == 0 ? 6.0 : (abs(y) == 1 ? 4.0 : 1.0);
        vec2 sampleUV = sourceUV + vec2(float(x), float(y)) * uiPixel * radius;
        vec2 coverage = smoothstep(-footprint, footprint, sampleUV)
          * (1.0 - smoothstep(vec2(1.0) - footprint, vec2(1.0) + footprint, sampleUV));
        color += textureLod(map, clamp(sampleUV, vec2(0.0), vec2(1.0)), lod).rgb
          * coverage.x * coverage.y * wx * wy / 256.0;
      }
    }
  }
  return color * (1.0 - min(1.0, effect * 2.0));
}
`;
const foldShader = `
uniform float foldAngle;
vec2 rotateHinge(vec2 p) {
  float c = cos(foldAngle), s = sin(foldAngle);
  p.y -= 0.275454;
  return vec2(c * p.x + s * p.y, -s * p.x + c * p.y + 0.275454);
}
#ifdef FLEXIBLE_SCREEN
vec4 bendStrip(vec3 p) {
  float halfWidth = 0.35;
  if (p.x >= halfWidth) return vec4(p.x, p.z, 1.0, 0.0);
  if (p.x <= -halfWidth) return vec4(rotateHinge(p.xz), cos(foldAngle), -sin(foldAngle));
  float t = (p.x + halfWidth) / (2.0 * halfWidth);
  float t2 = t*t, t3 = t2*t;
  vec2 a = rotateHinge(vec2(-halfWidth, p.z));
  vec2 b = vec2(halfWidth, p.z);
  vec2 ta = 2.0 * halfWidth * vec2(cos(foldAngle), -sin(foldAngle));
  vec2 tb = vec2(2.0 * halfWidth, 0.0);
  vec2 point = (2.0*t3-3.0*t2+1.0)*a + (t3-2.0*t2+t)*ta + (-2.0*t3+3.0*t2)*b + (t3-t2)*tb;
  vec2 tangent = normalize((6.0*t2-6.0*t)*a + (3.0*t2-4.0*t+1.0)*ta + (-6.0*t2+6.0*t)*b + (3.0*t2-2.0*t)*tb);
  return vec4(point, tangent);
}
#endif
`;
const model = await new USDLoader().loadAsync('./assets/iPhone_Duo_Render.usdc');
model.scale.multiplyScalar(100);
model.updateMatrixWorld(true);
model.traverse(object => {
  if (!object.isMesh) return;
  const geometry = object.geometry.clone().applyMatrix4(object.matrixWorld);
  geometry.translate(0, -5.8974, 0);
  let ancestor = object;
  while (ancestor && !['upTUAKvMVkPOMKq', 'SiftyleUEEZwLhF'].includes(ancestor.name)) ancestor = ancestor.parent;
  const moving = ancestor?.name === 'upTUAKvMVkPOMKq';
  const flexible = ['JnJdTkxbQgUtLwU', 'xdyyaajWsatVNxN', 'UXtsBZYlaUvHoEh', 'MvKPXGSdYDVvSpk'].includes(object.name);
  const kind = object.name === 'UXtsBZYlaUvHoEh' ? 'inner' : object.name === 'hhgAIoCGsHXeDPY' ? 'outer' : null;
  const material = kind ? screens[kind].material : object.material.clone();
  if (kind) {
    const p = geometry.attributes.position;
    const uv = new Float32Array(p.count * 2);
    for (let i = 0; i < p.count; i++) {
      uv[i * 2] = kind === 'inner' ? (p.getX(i) + 7.89935) / 15.7987 : (-.23396 - p.getX(i)) / 7.73936;
      uv[i * 2 + 1] = kind === 'inner' ? (p.getY(i) + 5.8974 - .34562) / 11.1035 : (p.getY(i) + 5.8974 - .27173) / 11.2513;
    }
    geometry.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  }
  if (moving || flexible) {
    material.onBeforeCompile = shader => {
      shader.uniforms.foldAngle = bend;
      if (kind) {
        shader.uniforms.uiFrame = screens[kind].frame;
        shader.uniforms.uiGradient = screens[kind].gradient;
        shader.uniforms.uiReferenceEye = { value: uiReferenceEye };
        shader.uniforms.uiPixel = screens[kind].pixel;
        shader.uniforms.uiBlur = screens[kind].blur;
        shader.fragmentShader = shader.fragmentShader.replace('#include <map_pars_fragment>', `
          #include <map_pars_fragment>
          ${kind === 'inner' ? '#define INNER_UI' : ''}
          ${screenShader}
        `).replace('#include <map_fragment>', 'diffuseColor.rgb *= screenColor();');
        shader.vertexShader = `varying vec3 vUIPosition;\n${shader.vertexShader}`;
        shader.vertexShader = shader.vertexShader.replace('#include <project_vertex>', `
          vUIPosition = transformed;
          #include <project_vertex>
        `);
      }
      shader.vertexShader = `${flexible ? '#define FLEXIBLE_SCREEN\n' : ''}${foldShader}\n${shader.vertexShader}`;
      shader.vertexShader = shader.vertexShader.replace('#include <begin_vertex>', flexible ? `
        vec4 folded = bendStrip(position);
        vec3 transformed = vec3(folded.x, position.y, folded.y);
      ` : `
        vec2 folded = rotateHinge(position.xz);
        vec3 transformed = vec3(folded.x, position.y, folded.y);
      `);
      shader.vertexShader = shader.vertexShader.replace('#include <beginnormal_vertex>', `
        vec3 objectNormal = vec3(normal);
        ${flexible ? 'vec4 strip = bendStrip(position); float a = atan(-strip.w, strip.z);' : 'float a = foldAngle;'}
        objectNormal.x = cos(a) * normal.x + sin(a) * normal.z;
        objectNormal.z = -sin(a) * normal.x + cos(a) * normal.z;
      `);
    };
    material.customProgramCacheKey = () => `${flexible ? 'fold-flexible' : 'fold-cover'}-${kind || 'body'}`;
  }
  const mesh = new THREE.Mesh(geometry, material);
  mesh.castShadow = !kind;
  mesh.frustumCulled = false;
  phone.add(mesh);
});

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
// a screen's picture as compose.html drew it, into its canvas: the whole of it (its aspect the screen's own)
// (and where a finger is on it, `touches` (compose_sim.mjs touchesAt): a disc where it is down, a ring opening as it is
// lifted, the way a drag came behind it)
async function show(kind, url, shown, touches = []) {
  const s = screens[kind];
  const key = url + JSON.stringify(touches);
  if (s.shown === key) return;
  s.shown = key;
  const c = s.canvas.getContext('2d');
  const img = await picture(url);
  c.fillStyle = '#000';
  c.fillRect(0, 0, s.canvas.width, s.canvas.height);
  if (img && shown) c.drawImage(img, 0, 0, s.canvas.width, s.canvas.height);
  if (shown) {
    const H = s.canvas.height, W = s.canvas.width, r0 = H * .03;
    for (const { at: [x, y], down, lift, trail } of touches) {
      // the way a drag came: a band narrowing and fading behind the finger
      for (let j = 1; j < trail.length; j++) {
        const f = j / trail.length;
        c.beginPath();
        c.moveTo(trail[j - 1][0] * W, trail[j - 1][1] * H);
        c.lineTo(trail[j][0] * W, trail[j][1] * H);
        c.lineCap = 'round';
        c.lineWidth = r0 * 1.4 * f;
        c.strokeStyle = `rgba(40,40,48,${.22 * f * down * (1 - lift)})`;
        c.stroke();
      }
      const k = down * (1 - lift);
      c.beginPath();
      c.arc(x * W, y * H, r0 * (1 - .15 * lift), 0, Math.PI * 2);
      c.fillStyle = `rgba(40,40,48,${.42 * k})`;
      c.fill();
      c.lineWidth = H * .003;
      c.strokeStyle = `rgba(255,255,255,${.85 * k})`;
      c.stroke();
      // lifted: a ring opening round where it was
      if (lift > 0) {
        c.beginPath();
        c.arc(x * W, y * H, r0 * (1 + 1.4 * lift), 0, Math.PI * 2);
        c.lineWidth = H * .004 * (1 - lift);
        c.strokeStyle = `rgba(40,40,48,${.35 * (1 - lift)})`;
        c.stroke();
      }
    }
  }
  s.texture.needsUpdate = true;
}

/**
 * One frame: `angle` how far it is open (0 folded, 180 flat, the reference's slider), the screens' pictures, and the
 * camera: looking at (x, y) of the open phone's units from `dist` away, turned `yaw` degrees about its upright axis
 * and `pitch` about its sideways one.
 */
window.frame3d = async ({ outer, inner, angle, cam, touches = {} }) => {
  bend.value = (180 - angle) / 180 * Math.PI;
  await show('outer', outer, angle < 180, touches.outer);
  await show('inner', inner, angle > 0, touches.inner);
  const [dist, x, y, yaw = 0, pitch = 0] = cam;
  const target = new THREE.Vector3(x, y, .275454);
  const dir = new THREE.Vector3(Math.sin(THREE.MathUtils.degToRad(yaw)) * Math.cos(THREE.MathUtils.degToRad(pitch)),
    Math.sin(THREE.MathUtils.degToRad(pitch)), Math.cos(THREE.MathUtils.degToRad(yaw)) * Math.cos(THREE.MathUtils.degToRad(pitch)));
  camera.position.copy(target).addScaledVector(dir, dist);
  camera.lookAt(target);
  renderer.render(scene, camera);
};
window.ready3d = true;
