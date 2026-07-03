Paste these into CodePen’s **HTML**, **CSS**, and **JS** panels. It makes a procedural tree where branches are controlled by degree-based rules: pitch angle, randomness, depth, shrink, child count, and wind sway. Shocking development: trees are just trigonometry wearing bark.

## HTML

```html
<div class="app">
  <aside class="panel">
    <h1>Degree-Based Procedural Tree</h1>
    <p>
      Recursive branch math using angle, length shrink, radius shrink, seed randomness,
      and animated wind.
    </p>

    <label>
      Seed
      <input id="seed" type="number" value="12345" />
    </label>

    <label>
      Depth
      <input id="depth" type="range" min="1" max="10" value="7" />
      <span id="depthValue"></span>
    </label>

    <label>
      Branch Pitch Degrees
      <input id="pitch" type="range" min="5" max="85" value="38" />
      <span id="pitchValue"></span>
    </label>

    <label>
      Angle Randomness
      <input id="randomness" type="range" min="0" max="45" value="13" />
      <span id="randomnessValue"></span>
    </label>

    <label>
      Child Branches
      <input id="children" type="range" min="1" max="5" value="2" />
      <span id="childrenValue"></span>
    </label>

    <label>
      Length Shrink
      <input id="lengthShrink" type="range" min="40" max="90" value="72" />
      <span id="lengthShrinkValue"></span>
    </label>

    <label>
      Radius Shrink
      <input id="radiusShrink" type="range" min="45" max="85" value="68" />
      <span id="radiusShrinkValue"></span>
    </label>

    <label>
      Leaf Density
      <input id="leafDensity" type="range" min="0" max="20" value="8" />
      <span id="leafDensityValue"></span>
    </label>

    <label>
      Wind Strength
      <input id="wind" type="range" min="0" max="100" value="28" />
      <span id="windValue"></span>
    </label>

    <div class="buttons">
      <button id="generate">Generate Tree</button>
      <button id="randomSeed">Random Seed</button>
    </div>

    <div class="hint">
      Try pitch 20° for tall trees, 55° for wide trees, and high randomness for dead/fantasy trees.
    </div>
  </aside>

  <main class="canvas-wrap">
    <canvas id="treeCanvas"></canvas>
  </main>
</div>
```

## CSS

```css
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  overflow: hidden;
  background: #111827;
  color: #e5e7eb;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

.app {
  display: grid;
  grid-template-columns: 320px 1fr;
  width: 100vw;
  height: 100vh;
}

.panel {
  padding: 18px;
  background: #0f172a;
  border-right: 1px solid rgba(255, 255, 255, 0.08);
  overflow-y: auto;
}

h1 {
  margin: 0 0 8px;
  font-size: 20px;
}

p {
  margin: 0 0 18px;
  color: #94a3b8;
  line-height: 1.4;
  font-size: 14px;
}

label {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 6px;
  margin-bottom: 15px;
  font-size: 13px;
  color: #cbd5e1;
}

input[type="range"] {
  grid-column: 1 / 3;
  width: 100%;
}

input[type="number"] {
  grid-column: 1 / 3;
  width: 100%;
  background: #020617;
  border: 1px solid #334155;
  color: #e5e7eb;
  padding: 8px;
  border-radius: 8px;
}

.buttons {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin: 18px 0;
}

button {
  border: 0;
  border-radius: 10px;
  padding: 10px 12px;
  color: #0f172a;
  background: #93c5fd;
  font-weight: 700;
  cursor: pointer;
}

button:hover {
  background: #bfdbfe;
}

.hint {
  margin-top: 15px;
  padding: 12px;
  border-radius: 12px;
  background: rgba(147, 197, 253, 0.1);
  color: #bfdbfe;
  font-size: 13px;
  line-height: 1.4;
}

.canvas-wrap {
  position: relative;
  width: 100%;
  height: 100%;
  background:
    radial-gradient(circle at 50% 20%, rgba(96, 165, 250, 0.18), transparent 35%),
    linear-gradient(#172554, #0f172a 45%, #111827 70%, #0b1120);
}

canvas {
  display: block;
  width: 100%;
  height: 100%;
}
```

## JS

```js
const canvas = document.getElementById("treeCanvas");
const ctx = canvas.getContext("2d");

const controls = {
  seed: document.getElementById("seed"),
  depth: document.getElementById("depth"),
  pitch: document.getElementById("pitch"),
  randomness: document.getElementById("randomness"),
  children: document.getElementById("children"),
  lengthShrink: document.getElementById("lengthShrink"),
  radiusShrink: document.getElementById("radiusShrink"),
  leafDensity: document.getElementById("leafDensity"),
  wind: document.getElementById("wind")
};

const labels = {
  depth: document.getElementById("depthValue"),
  pitch: document.getElementById("pitchValue"),
  randomness: document.getElementById("randomnessValue"),
  children: document.getElementById("childrenValue"),
  lengthShrink: document.getElementById("lengthShrinkValue"),
  radiusShrink: document.getElementById("radiusShrinkValue"),
  leafDensity: document.getElementById("leafDensityValue"),
  wind: document.getElementById("windValue")
};

const generateButton = document.getElementById("generate");
const randomSeedButton = document.getElementById("randomSeed");

let branches = [];
let leaves = [];
let time = 0;

function resizeCanvas() {
  const rect = canvas.parentElement.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;

  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;

  canvas.style.width = `${rect.width}px`;
  canvas.style.height = `${rect.height}px`;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  generateTree();
}

window.addEventListener("resize", resizeCanvas);

function degToRad(deg) {
  return deg * Math.PI / 180;
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

// Seeded random generator. Same seed = same tree.
function mulberry32(seed) {
  return function () {
    let t = seed += 0x6D2B79F5;
    t = Math.imul(t ^ t >>> 15, t | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

function randRange(rng, min, max) {
  return min + rng() * (max - min);
}

function getSettings() {
  return {
    seed: Number(controls.seed.value) || 1,
    depth: Number(controls.depth.value),
    pitch: Number(controls.pitch.value),
    randomness: Number(controls.randomness.value),
    children: Number(controls.children.value),
    lengthShrink: Number(controls.lengthShrink.value) / 100,
    radiusShrink: Number(controls.radiusShrink.value) / 100,
    leafDensity: Number(controls.leafDensity.value),
    wind: Number(controls.wind.value) / 100
  };
}

function updateLabels() {
  const s = getSettings();

  labels.depth.textContent = s.depth;
  labels.pitch.textContent = `${s.pitch}°`;
  labels.randomness.textContent = `±${s.randomness}°`;
  labels.children.textContent = s.children;
  labels.lengthShrink.textContent = s.lengthShrink.toFixed(2);
  labels.radiusShrink.textContent = s.radiusShrink.toFixed(2);
  labels.leafDensity.textContent = s.leafDensity;
  labels.wind.textContent = s.wind.toFixed(2);
}

function generateTree() {
  updateLabels();

  branches = [];
  leaves = [];

  const s = getSettings();
  const rng = mulberry32(s.seed);

  const width = canvas.clientWidth;
  const height = canvas.clientHeight;

  const startX = width * 0.5;
  const startY = height * 0.9;

  const trunkLength = Math.min(width, height) * 0.22;
  const trunkRadius = Math.min(width, height) * 0.025;

  growBranch({
    x: startX,
    y: startY,
    angle: -90,
    length: trunkLength,
    radius: trunkRadius,
    depth: s.depth,
    maxDepth: s.depth,
    rng,
    settings: s,
    generation: 0
  });
}

function growBranch({
  x,
  y,
  angle,
  length,
  radius,
  depth,
  maxDepth,
  rng,
  settings,
  generation
}) {
  if (depth <= 0 || radius < 0.7 || length < 2) {
    addLeaves(x, y, radius, rng, settings, generation);
    return;
  }

  // Slight upward bias keeps the tree from collapsing sideways like a lazy antenna.
  const upBias = lerp(0.12, 0.03, depth / maxDepth);
  const biasedAngle = lerp(angle, -90, upBias);

  const rad = degToRad(biasedAngle);

  const endX = x + Math.cos(rad) * length;
  const endY = y + Math.sin(rad) * length;

  const phase = randRange(rng, 0, Math.PI * 2);
  const curveAmount = randRange(rng, -0.25, 0.25) * length;

  branches.push({
    x,
    y,
    endX,
    endY,
    angle: biasedAngle,
    length,
    radius,
    depth,
    maxDepth,
    phase,
    curveAmount,
    generation
  });

  const childCount = Math.max(1, settings.children);
  const sideStart = childCount === 1 ? 0 : -(childCount - 1) / 2;

  for (let i = 0; i < childCount; i++) {
    const side = sideStart + i;

    // This is the core degree math:
    // child_angle = parent_angle + pitch_offset + random_offset
    const pitchOffset = side * settings.pitch;
    const randomOffset = randRange(
      rng,
      -settings.randomness,
      settings.randomness
    );

    // Tiny extra spiral-ish offset, useful even in 2D to avoid symmetry.
    const goldenJitter = ((generation * 137.5 + i * 37.7) % 24) - 12;

    const childAngle = biasedAngle + pitchOffset + randomOffset + goldenJitter;

    const childLength = length * randRange(
      rng,
      settings.lengthShrink * 0.9,
      settings.lengthShrink * 1.05
    );

    // Leonardo-ish branch shrink approximation:
    // child radius gets smaller per generation.
    const childRadius = radius * randRange(
      rng,
      settings.radiusShrink * 0.9,
      settings.radiusShrink * 1.05
    );

    growBranch({
      x: endX,
      y: endY,
      angle: childAngle,
      length: childLength,
      radius: childRadius,
      depth: depth - 1,
      maxDepth,
      rng,
      settings,
      generation: generation + 1
    });
  }

  // Add a few leaves near upper branch tips.
  if (depth <= 3) {
    addLeaves(endX, endY, radius, rng, settings, generation);
  }
}

function addLeaves(x, y, radius, rng, settings, generation) {
  const count = Math.floor(settings.leafDensity * randRange(rng, 0.5, 1.4));

  for (let i = 0; i < count; i++) {
    const dist = randRange(rng, 4, 28);
    const angle = randRange(rng, 0, Math.PI * 2);

    leaves.push({
      x: x + Math.cos(angle) * dist,
      y: y + Math.sin(angle) * dist,
      baseX: x,
      baseY: y,
      size: randRange(rng, 2.5, 6.5),
      phase: randRange(rng, 0, Math.PI * 2),
      sway: randRange(rng, 2, 12),
      hue: randRange(rng, 85, 135),
      lightness: randRange(rng, 28, 48),
      generation
    });
  }
}

function drawBackground() {
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;

  ctx.clearRect(0, 0, width, height);

  // Ground.
  ctx.fillStyle = "#11110d";
  ctx.fillRect(0, height * 0.9, width, height * 0.1);

  // Soft moon/sun thing. Very scientific, obviously.
  const glow = ctx.createRadialGradient(
    width * 0.52,
    height * 0.18,
    10,
    width * 0.52,
    height * 0.18,
    height * 0.45
  );

  glow.addColorStop(0, "rgba(191, 219, 254, 0.35)");
  glow.addColorStop(1, "rgba(191, 219, 254, 0)");

  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, width, height);
}

function drawBranches(settings) {
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  // Draw big branches first, tiny branches later.
  for (const b of branches) {
    const depthRatio = b.depth / b.maxDepth;
    const windAmount = settings.wind * (1 - depthRatio);

    const sway = Math.sin(time * 1.4 + b.phase) * windAmount * b.length * 0.08;

    const midX = (b.x + b.endX) * 0.5 + b.curveAmount + sway;
    const midY = (b.y + b.endY) * 0.5;

    const bark = Math.floor(80 + depthRatio * 45);
    ctx.strokeStyle = `rgb(${bark}, ${Math.floor(bark * 0.66)}, ${Math.floor(bark * 0.38)})`;
    ctx.lineWidth = Math.max(1, b.radius);

    ctx.beginPath();
    ctx.moveTo(b.x, b.y);
    ctx.quadraticCurveTo(midX, midY, b.endX + sway, b.endY);
    ctx.stroke();
  }
}

function drawLeaves(settings) {
  for (const leaf of leaves) {
    const windX = Math.sin(time * 2.8 + leaf.phase) * leaf.sway * settings.wind;
    const windY = Math.cos(time * 3.3 + leaf.phase) * leaf.sway * settings.wind * 0.25;

    const x = leaf.x + windX;
    const y = leaf.y + windY;

    ctx.fillStyle = `hsl(${leaf.hue}, 48%, ${leaf.lightness}%)`;

    ctx.beginPath();
    ctx.ellipse(
      x,
      y,
      leaf.size * 1.25,
      leaf.size * 0.85,
      Math.sin(time + leaf.phase) * 0.4,
      0,
      Math.PI * 2
    );
    ctx.fill();
  }
}

function drawDebugFormula() {
  ctx.save();

  ctx.fillStyle = "rgba(15, 23, 42, 0.68)";
  ctx.fillRect(20, 20, 430, 76);

  ctx.fillStyle = "#e5e7eb";
  ctx.font = "13px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";

  ctx.fillText("child_angle = parent_angle + pitch + random_offset", 36, 45);
  ctx.fillText("child_length = parent_length × length_shrink", 36, 66);
  ctx.fillText("child_radius = parent_radius × radius_shrink", 36, 87);

  ctx.restore();
}

function animate() {
  time += 0.016;

  const settings = getSettings();

  drawBackground();
  drawBranches(settings);
  drawLeaves(settings);
  drawDebugFormula();

  requestAnimationFrame(animate);
}

Object.values(controls).forEach(input => {
  input.addEventListener("input", () => {
    generateTree();
  });
});

generateButton.addEventListener("click", generateTree);

randomSeedButton.addEventListener("click", () => {
  controls.seed.value = Math.floor(Math.random() * 999999);
  generateTree();
});

resizeCanvas();
animate();
```

The important part is this:

```js
const childAngle = parentAngle + pitchOffset + randomOffset + goldenJitter;
```

That is the whole “branches form within a degree range” idea in one line. Everything else is just making it look less like a sad fork.
