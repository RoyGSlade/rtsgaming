<canvas id="webgl_canvas"></canvas>
<div id="hud">
  <div id="hud_pct">000%</div>
  <div class="progress-bar">
    <div class="progress-fill" id="prog_fill"></div>
  </div>
  <div class="scene-label" id="scene_name">DAWN</div>
</div>
<button id="theme_toggle" aria-label="Toggle light/dark mode">
  <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
  </svg>
  <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
    <path d="M21 12.79A9 9 0 1 1 11.21 3a7 7 0 0 0 9.79 9.79z" />
  </svg>
</button>
<div id="scene_strip">
  <div class="scene-dot active"></div>
  <div class="scene-dot"></div>
  <div class="scene-dot"></div>
  <div class="scene-dot"></div>
  <div class="scene-dot"></div>
</div>
<div id="scroll_container">
  <section id="s0">
    <div class="text-card">
      <div class="tag">A small reflection</div>
      <h1>THE<br>ENDLESS<br>HORIZON</h1>
      <p class="body-text">
        A small build during a quiet pause. Scroll and watch the sea move
        through a full day. Light changes, waves repeat, and the horizon
        keeps returning.
      </p>
      <a class="cta" href="#s1">
        Continue
        <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M1 6h10M6 1l5 5-5 5" />
        </svg>
      </a>
    </div>
  </section>
  <section id="s1">
    <div class="text-card right">
      <div class="h-line"></div>
      <div class="tag">01 — Midday</div>
      <h2>OPEN<br>WATER</h2>
      <p class="body-text">
        Reconnecting with simplicity. Small pieces of motion, repeating
        quietly. For a moment the rhythm feels calm, almost balanced.
      </p>
      <div class="stat-row" style="justify-content: flex-end">
        <div class="stat">
          <span class="stat-num">360°</span>
          <span class="stat-label">Horizon</span>
        </div>
        <div class="stat">
          <span class="stat-num">5</span>
          <span class="stat-label">Phases</span>
        </div>
        <div class="stat">
          <span class="stat-num">∞</span>
          <span class="stat-label">Motion</span>
        </div>
      </div>
    </div>
  </section>
  <section id="s2">
    <div class="text-card">
      <div class="h-line"></div>
      <div class="tag">02 — Sunset</div>
      <h2>SHIFTING<br>LIGHT</h2>
      <p class="body-text">
        Still, the calm carries a question. Is this something honest being
        rebuilt, or just a way of avoiding what comes next?
      </p>
      <a class="cta" href="#s3">
        Continue
        <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M1 6h10M6 1l5 5-5 5" />
        </svg>
      </a>
    </div>
  </section>
  <section id="s3">
    <div class="text-card center">
      <div class="h-line"></div>
      <div class="tag">03 — Midnight</div>
      <h2>QUIET<br>SEA</h2>
      <p class="body-text">
        Simplicity can restore focus, but it can also soften the edge.
        Stay there too long and comfort begins to blur into confusion.
      </p>
    </div>
  </section>
  <section id="s4">
    <div class="text-card right">
      <div class="h-line"></div>
      <div class="tag">04 — Storm</div>
      <h2>THE<br>QUESTION</h2>
      <p class="body-text">
        The waves keep cycling. For now that is enough. But beneath the calm
        the question remains, waiting for whatever comes next.
      </p>
      <a class="cta" href="#s0">
        Begin again
        <svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M1 6h10M6 1l5 5-5 5" />
        </svg>
      </a>
    </div>
  </section>
</div>
<div id="credit">
  <a href="https://www.lessrain.com" target="_blank" rel="noopener">
    LESS RAIN GMBH
  </a>
</div>

@import url("https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@300;400&display=swap");

*,
*::before,
*::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

:root {
  color-scheme: dark;

  --dark-bg: #0a0a0f;
  --dark-fg: #e8e4d9;
  --dark-muted: #6a6a7e;
  --dark-accent: #c8ff47;
  --dark-card-bg: rgba(10, 10, 15, 0.16);
  --dark-card-border: rgba(200, 255, 71, 0.18);

  --light-bg: #eef4ff;
  --light-fg: #0b141a;
  --light-muted: #6c8296;
  --light-accent: #1b7ed6;
  --light-card-bg: rgba(245, 249, 255, 0.82);
  --light-card-border: rgba(27, 126, 214, 0.22);

  --bg: var(--dark-bg);
  --fg: var(--dark-fg);
  --muted: var(--dark-muted);
  --accent: var(--dark-accent);
  --card-bg: var(--dark-card-bg);
  --card-border: var(--dark-card-border);

  --font-display: "Bebas Neue", sans-serif;
  --font-mono: "DM Mono", monospace;
  --hairline: 0.0625rem;
  --ui-inset: 2rem;
  --nav-x: calc(var(--ui-inset) + 0.125rem);
  --reveal-offset: 0.625rem;
  --reveal-duration: 0.5s;
  --card-radius: 0.875rem;
  --z-ui: 10;
}

:root[data-theme="light"] {
  color-scheme: light;

  --bg: var(--light-bg);
  --fg: var(--light-fg);
  --muted: var(--light-muted);
  --accent: var(--light-accent);
  --card-bg: var(--light-card-bg);
  --card-border: var(--light-card-border);
}

html {
  color-scheme: dark;
}

body {
  background: var(--bg);
  color: var(--fg);
  font-family: var(--font-mono);
  overflow-x: hidden;
  transition: background 0.3s ease, color 0.3s ease;
}

#webgl_canvas {
  position: fixed;
  inset: 0;
  width: 100vw;
  height: 100vh;
  height: 100dvh;
  z-index: 0;
  pointer-events: none;
}

#hud {
  position: fixed;
  top: var(--ui-inset);
  right: var(--ui-inset);
  z-index: var(--z-ui);
  text-align: right;
  font-size: 0.65rem;
  letter-spacing: 0.15em;
  color: var(--muted);
  text-transform: uppercase;
}

#hud .progress-bar {
  width: 7.5rem;
  height: var(--hairline);
  background: var(--muted);
  margin-block-start: 0.5rem;
  margin-inline-start: auto;
  position: relative;
  overflow: hidden;
}

#hud .progress-fill {
  position: absolute;
  inset-block: 0;
  inset-inline-start: 0;
  width: 0%;
  background: var(--accent);
  transition: width 0.1s linear;
}

#hud .scene-label {
  font-size: 0.6rem;
  color: var(--accent);
  margin-block-start: 0.4rem;
}

#scene_strip {
  position: fixed;
  left: var(--nav-x);
  top: 50%;
  translate: -50% -50%;
  z-index: var(--z-ui);
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.scene-dot {
  width: 0.25rem;
  height: 0.25rem;
  border-radius: 50%;
  background: var(--muted);
  transition: background 0.3s, scale 0.3s;
}

.scene-dot.active {
  background: var(--accent);
  scale: 1.8;
}

#theme_toggle {
  position: fixed;
  bottom: var(--ui-inset);
  left: var(--nav-x);
  translate: -50% 0;
  z-index: var(--z-ui);
  width: 2rem;
  height: 2rem;
  border: none;
  background: color-mix(in srgb, var(--muted) 35%, transparent);
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.3s;
}

#theme_toggle:hover {
  background: color-mix(in srgb, var(--muted) 55%, transparent);
}

#theme_toggle svg {
  width: 0.875rem;
  height: 0.875rem;
  position: absolute;
  transition: opacity 0.3s ease, rotate 0.3s ease;
  color: var(--accent);
}

:root[data-theme="light"] #theme_toggle svg {
  color: var(--fg);
}

#theme_toggle .icon-sun {
  opacity: 1;
  rotate: 0deg;
}

#theme_toggle .icon-moon {
  opacity: 0;
  rotate: 90deg;
}

:root[data-theme="light"] #theme_toggle .icon-sun {
  opacity: 0;
  rotate: -90deg;
}

:root[data-theme="light"] #theme_toggle .icon-moon {
  opacity: 1;
  rotate: 0deg;
}

#scroll_container {
  position: relative;
  z-index: 1;
}

section {
  min-height: 100vh;
  display: flex;
  align-items: center;
  padding: 6rem 5rem;
}

.text-card {
  max-width: 23.75rem;
  padding: 2.25rem 2rem;
  background: var(--card-bg);
  border-left: var(--hairline) solid var(--card-border);
  transition: background 0.3s ease, border-color 0.3s ease;
}

:root[data-theme="dark"] .text-card {
  border: var(--hairline) solid var(--card-border);
  border-radius: var(--card-radius);
  backdrop-filter: blur(14px) saturate(130%);
  -webkit-backdrop-filter: blur(14px) saturate(130%);
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
}

.text-card.right {
  margin-inline-start: auto;
  border-left: none;
  border-right: var(--hairline) solid var(--card-border);
  text-align: right;
}

.text-card.center {
  margin-inline: auto;
  border-left: none;
  border-top: var(--hairline) solid var(--card-border);
  text-align: center;
  max-width: 28.75rem;
}

.tag {
  font-size: 0.6rem;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  color: var(--accent);
  margin-block-end: 1.1rem;
  opacity: 0;
  translate: 0 var(--reveal-offset);
  transition: opacity var(--reveal-duration) ease,
    translate var(--reveal-duration) ease;
}

.tag.visible {
  opacity: 1;
  translate: 0 0;
}

:is(h1, h2) {
  font-family: var(--font-display);
  font-weight: 400;
  letter-spacing: 0.03em;
  line-height: 0.92;
  opacity: 0;
  translate: 0 1.125rem;
  transition: opacity var(--reveal-duration) ease 0.08s,
    translate var(--reveal-duration) ease 0.08s;
}

:is(h1, h2).visible {
  opacity: 1;
  translate: 0 0;
}

h1 {
  font-size: clamp(3rem, 8vw, 6.5rem);
}

h2 {
  font-size: clamp(2.2rem, 6vw, 5rem);
}

.body-text {
  font-size: 0.78rem;
  line-height: 1.8;
  color: color-mix(in srgb, var(--fg) 55%, transparent);
  margin-block-start: 1.25rem;
  opacity: 0;
  translate: 0 var(--reveal-offset);
  transition: opacity var(--reveal-duration) ease 0.2s,
    translate var(--reveal-duration) ease 0.2s;
}

.body-text.visible {
  opacity: 1;
  translate: 0 0;
}

.stat-row {
  display: flex;
  gap: 2.5rem;
  margin-block-start: 2rem;
  flex-wrap: wrap;
  opacity: 0;
  translate: 0 var(--reveal-offset);
  transition: opacity var(--reveal-duration) ease 0.3s,
    translate var(--reveal-duration) ease 0.3s;
}

.stat-row.visible {
  opacity: 1;
  translate: 0 0;
}

.stat {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.stat-num {
  font-family: var(--font-display);
  font-size: 2.2rem;
  color: var(--accent);
  line-height: 1;
}

.stat-label {
  font-size: 0.58rem;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--muted);
}

.h-line {
  width: 3.125rem;
  height: var(--hairline);
  background: var(--accent);
  margin-block-end: 1.2rem;
  opacity: 0;
  scale: 0 1;
  transform-origin: left;
  transition: opacity 0.4s ease, scale 0.4s ease;
}

.h-line.visible {
  opacity: 1;
  scale: 1 1;
}

.text-card.right .h-line {
  transform-origin: right;
  margin-inline-start: auto;
}

.text-card.center .h-line {
  transform-origin: center;
  margin-inline: auto;
  margin-block-end: 1.2rem;
}

.cta {
  display: inline-flex;
  align-items: center;
  gap: 0.6rem;
  margin-block-start: 1.75rem;
  padding: 0.6rem 1.25rem;
  border: var(--hairline) solid var(--accent);
  color: var(--accent);
  font-family: var(--font-mono);
  font-size: 0.62rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  text-decoration: none;
  cursor: pointer;
  opacity: 0;
  translate: 0 var(--reveal-offset);
  transition: opacity var(--reveal-duration) ease 0.35s,
    translate var(--reveal-duration) ease 0.35s, background 0.2s, color 0.2s;
}

.cta.visible {
  opacity: 1;
  translate: 0 0;
}

.cta:hover {
  background: var(--accent);
  color: var(--bg);
}

.cta svg {
  width: 0.6875rem;
  height: 0.6875rem;
}

#credit {
  position: fixed;
  right: var(--ui-inset);
  top: 50%;
  transform: translateY(-50%) rotate(-90deg);
  transform-origin: right center;
  z-index: var(--z-ui);
  font-family: var(--font-mono);
  font-size: 0.65rem;
  letter-spacing: 0.15em;
}

#credit a {
  color: var(--muted);
  text-decoration: none;
}

@media (width <= 60em) {
  section {
    padding: 5rem 3rem;
  }

  .text-card {
    max-width: 20rem;
  }
}

@media (width <= 37.5em) {
  :root {
    --ui-inset: 1.25rem;
  }

  section {
    padding: 4rem 1.25rem;
  }

  .text-card {
    max-width: 100%;
  }

  .text-card:is(.right, .center) {
    margin-inline: 0;
    text-align: left;
    border-right: none;
    border-top: none;
    border-left: var(--hairline) solid var(--card-border);
  }

  .text-card:is(.right, .center) .h-line {
    transform-origin: left;
    margin-inline-start: 0;
    margin-inline: 0;
  }

  #hud {
    top: 1rem;
    right: 1rem;
  }

  #scene_strip {
    display: none;
  }

  #theme_toggle {
    bottom: 1rem;
    left: 1.25rem;
    translate: 0 0;
  }

  .stat-row {
    gap: 1.5rem;
  }
}

const canvas = document.getElementById("webgl_canvas");
const gl = canvas.getContext("webgl", {
  alpha: false,
  antialias: false,
  depth: false,
  stencil: false,
  preserveDrawingBuffer: false,
  powerPreference: "high-performance"
});

if (!gl) {
  canvas.style.background = "#0a0a0f";
  throw new Error("WebGL not supported");
}

const vs = `
attribute vec2 a;
void main() {
  gl_Position = vec4(a, 0.0, 1.0);
}
`;

const fs = `
precision highp float;

uniform vec2  uR;
uniform float uT, uS, uSc, uBl;
uniform vec3  uBg;

#define PI 3.14159265359
#define TAU 6.28318530718
#define MARCH_STEPS 22
#define REFINE_STEPS 5

float sat(float x) {
  return clamp(x, 0.0, 1.0);
}

float smoother(float x) {
  x = sat(x);
  return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

vec3 sCol(vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4) {
  int si = int(uSc);
  vec3 a = c0;
  vec3 b = c1;
  if (si == 1) { a = c1; b = c2; }
  else if (si == 2) { a = c2; b = c3; }
  else if (si == 3) { a = c3; b = c4; }
  return mix(a, b, uBl);
}

float sF(float c0, float c1, float c2, float c3, float c4) {
  int si = int(uSc);
  float a = c0;
  float b = c1;
  if (si == 1) { a = c1; b = c2; }
  else if (si == 2) { a = c2; b = c3; }
  else if (si == 3) { a = c3; b = c4; }
  return mix(a, b, uBl);
}

mat2 rot(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));

  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float waveH(vec2 p, float t, float amp, float storm) {
  float h = 0.0;

  vec2 swell1 = normalize(vec2(1.0, 0.28));
  vec2 swell2 = normalize(vec2(-0.48, 0.88));
  vec2 swell3 = normalize(vec2(0.82, -0.16));

  swell2 = rot(storm * 0.18) * swell2;
  swell3 = rot(-storm * 0.14) * swell3;

  float d1 = dot(p, swell1);
  float d2 = dot(p, swell2);
  float d3 = dot(p, swell3);

  h += amp * 0.66 * sin(d1 * 0.42 + t * 0.38);
  h += amp * 0.22 * sin(d1 * 0.94 - t * 0.62);
  h += amp * 0.14 * sin(d2 * 1.18 - t * 0.82);
  h += amp * 0.09 * sin(d3 * 1.82 + t * 1.04);

  h += amp * (0.11 + storm * 0.07) * sin(p.x * 1.45 - t * 0.76 + p.y * 0.66);
  h += amp * (0.07 + storm * 0.05) * sin(p.x * 2.85 + t * 1.06 - p.y * 0.52);
  h += amp * (0.04 + storm * 0.03) * sin(p.x * 4.60 - t * 1.50 + p.y * 1.02);

  float micro = noise(p * 14.0 + vec2(t * 0.18, t * 0.06)) - 0.5;
  h += micro * amp * (0.010 + storm * 0.008);

  return h;
}

vec3 waveNorm(vec2 p, float t, float amp, float storm) {
  float e = 0.018;
  float hL = waveH(p - vec2(e, 0.0), t, amp, storm);
  float hR = waveH(p + vec2(e, 0.0), t, amp, storm);
  float hD = waveH(p - vec2(0.0, e), t, amp, storm);
  float hU = waveH(p + vec2(0.0, e), t, amp, storm);
  return normalize(vec3(-(hR - hL) / (2.0 * e), 1.0, -(hU - hD) / (2.0 * e)));
}

float starField(vec2 uv) {
  vec2 gv = floor(uv);
  vec2 lv = fract(uv) - 0.5;

  float h = hash(gv);
  float size = mix(0.012, 0.0025, h);
  float d = length(lv + vec2(hash(gv + 3.1) - 0.5, hash(gv + 7.3) - 0.5) * 0.25);
  float star = smoothstep(size, 0.0, d);
  star *= smoothstep(0.82, 1.0, h);
  return star;
}

void main() {
  vec2 uv = (gl_FragCoord.xy - uR * 0.5) / uR.y;

  float s = smoother(uS);

  float camY = mix(1.14, 1.03, s);
  camY += sin(s * PI * 1.4) * 0.028;
  float camZ = mix(0.08, -0.18, s);
  float pitch = mix(0.115, 0.088, s);

  vec3 ro = vec3(0.0, camY, camZ);
  vec3 rd = normalize(vec3(uv.x, uv.y - pitch, -1.4));

  float storm = smoothstep(0.80, 1.0, s);
  float night = smoothstep(0.56, 0.84, s);

  vec3 skyTop = sCol(
    vec3(0.18, 0.06, 0.24),
    vec3(0.05, 0.24, 0.68),
    vec3(0.26, 0.06, 0.04),
    vec3(0.01, 0.01, 0.05),
    vec3(0.04, 0.05, 0.09)
  );

  vec3 skyHori = sCol(
    vec3(0.92, 0.48, 0.18),
    vec3(0.42, 0.62, 0.90),
    vec3(0.88, 0.32, 0.04),
    vec3(0.03, 0.05, 0.14),
    vec3(0.15, 0.17, 0.23)
  );

  vec3 sunCol = sCol(
    vec3(1.0, 0.62, 0.22),
    vec3(1.0, 0.96, 0.80),
    vec3(1.0, 0.38, 0.05),
    vec3(0.70, 0.75, 0.94),
    vec3(0.26, 0.28, 0.34)
  );

  vec3 seaDeep = sCol(
    vec3(0.08, 0.05, 0.12),
    vec3(0.03, 0.14, 0.34),
    vec3(0.10, 0.06, 0.04),
    vec3(0.00, 0.01, 0.03),
    vec3(0.03, 0.04, 0.07)
  );

  vec3 seaShlo = sCol(
    vec3(0.28, 0.17, 0.24),
    vec3(0.09, 0.38, 0.60),
    vec3(0.24, 0.13, 0.06),
    vec3(0.04, 0.06, 0.16),
    vec3(0.07, 0.10, 0.14)
  );

  vec3 fogCol = sCol(
    vec3(0.80, 0.50, 0.30),
    vec3(0.58, 0.72, 0.90),
    vec3(0.70, 0.28, 0.05),
    vec3(0.02, 0.03, 0.08),
    vec3(0.12, 0.14, 0.18)
  );

  float sunProgress = clamp(s / 0.58, 0.0, 1.0);
  float sunAngle = sunProgress * PI;
  float sunArcX = cos(sunAngle) * -0.75;
  float sunArcY = sin(sunAngle) * 0.38 - 0.08;

  vec3 sunDir = normalize(vec3(sunArcX, sunArcY, -1.0));
  vec3 moonDir = normalize(vec3(-0.14, 0.42, -1.0));

  float waveAmp = sF(0.082, 0.070, 0.100, 0.054, 0.30);
  waveAmp += storm * 0.020;

  float fogDen = sF(0.020, 0.010, 0.022, 0.034, 0.046);
  float moonAmt = sF(0.0, 0.0, 0.05, 0.92, 0.06);

  float sunAbove = step(0.0, sunDir.y);
  float sunGlow = smoothstep(-0.10, 0.06, sunDir.y);

  vec3 col;

  if (rd.y < 0.0) {
    float tFlat = ro.y / (-rd.y);
    float stepSize = tFlat / float(MARCH_STEPS);
    float t = stepSize;

    for (int i = 0; i < MARCH_STEPS; i++) {
      vec2 wpTest = ro.xz + rd.xz * t;
      float wy = ro.y + rd.y * t;
      if (wy < waveH(wpTest, uT, waveAmp, storm)) break;
      t += stepSize;
    }

    float ta = t - stepSize;
    float tb = t;

    for (int i = 0; i < REFINE_STEPS; i++) {
      float tm = (ta + tb) * 0.5;
      vec2 wpm = ro.xz + rd.xz * tm;
      if (ro.y + rd.y * tm < waveH(wpm, uT, waveAmp, storm)) tb = tm;
      else ta = tm;
    }

    t = (ta + tb) * 0.5;

    vec2 wp = ro.xz + rd.xz * t;
    vec3 n = waveNorm(wp, uT, waveAmp, storm);
    vec3 vDir = -rd;

    float fres = pow(1.0 - clamp(dot(n, vDir), 0.0, 1.0), 4.0);

    vec3 refl = reflect(rd, n);
    float rh = clamp(refl.y, 0.0, 1.0);

    vec3 reflSky = mix(skyHori, skyTop, pow(rh, 0.42));
    reflSky = mix(reflSky, skyHori, 0.12);

    float rSun = max(dot(refl, sunDir), 0.0);
    reflSky += sunCol * pow(rSun, 120.0) * 2.0 * sunGlow;
    reflSky += sunCol * pow(rSun, 18.0) * 0.07 * sunGlow;

    if (moonAmt > 0.04) {
      float rMoon = max(dot(refl, moonDir), 0.0);
      reflSky += vec3(0.72, 0.80, 0.95) * pow(rMoon, 120.0) * 0.78 * moonAmt;
    }

    float depth = exp(-t * 0.40);
    vec3 waterC = mix(seaDeep, seaShlo, depth * 0.5);

    vec3 absorb = vec3(0.85, 0.92, 1.0);
    waterC *= mix(vec3(1.0), absorb, clamp(t * 0.25, 0.0, 1.0));

    col = mix(waterC, reflSky, 0.15 + fres * 0.34);

    float spec = pow(max(dot(reflect(-sunDir, n), vDir), 0.0), 200.0);
    col += sunCol * spec * 1.10 * sunAbove;

    float broadSpec = pow(max(dot(reflect(-sunDir, n), vDir), 0.0), 32.0);
    col += sunCol * broadSpec * 0.12 * sunGlow;

    float sunLine = pow(max(dot(reflect(rd, n), sunDir), 0.0), 8.0);
    col += sunCol * sunLine * 0.48 * smoothstep(0.0, 0.35, -rd.y) * sunGlow;

    float sparkle = noise(wp * 18.0 + vec2(uT * 0.55, uT * 0.22));
    sparkle = smoothstep(0.94, 1.0, sparkle);
    col += sunCol * sparkle * 0.08 * sunGlow * sunAbove;

    if (moonAmt > 0.04) {
      float mSpec = pow(max(dot(reflect(-moonDir, n), vDir), 0.0), 520.0);
      col += vec3(0.72, 0.80, 0.95) * mSpec * 0.09 * moonAmt;
    }

    float hC = waveH(wp, uT, waveAmp, storm);
    float hL = waveH(wp - vec2(0.025, 0.0), uT, waveAmp, storm);
    float hR = waveH(wp + vec2(0.025, 0.0), uT, waveAmp, storm);
    float hD = waveH(wp - vec2(0.0, 0.025), uT, waveAmp, storm);
    float hU = waveH(wp + vec2(0.0, 0.025), uT, waveAmp, storm);

    float curvature = hR + hL + hU + hD - 4.0 * hC;
    float foam = clamp(curvature * (24.0 + storm * 10.0), 0.0, 1.0);
    col += foam * vec3(1.0) * (0.03 + storm * 0.10);

    float fog = 1.0 - exp(-t * fogDen * 1.65);
    col = mix(col, fogCol, fog);
  } else {
    float h = clamp(rd.y, 0.0, 1.0);
    col = mix(skyHori, skyTop, pow(h, 0.38));
  }

  float horizonW = 0.008;
  float skyMix = smoothstep(-horizonW, horizonW, rd.y);

  vec3 skyCol;
  {
    float h = clamp(rd.y, 0.0, 1.0);
    skyCol = mix(skyHori, skyTop, pow(h, 0.38));

    float cloudBand = noise(rd.x * 5.5 + vec2(rd.y * 3.0, uT * 0.015));
    float cloudBand2 = noise(rd.x * 8.0 - vec2(rd.y * 4.0, uT * 0.010));
    float clouds = smoothstep(0.62, 0.86, cloudBand * 0.65 + cloudBand2 * 0.35);
    clouds *= smoothstep(-0.02, 0.24, rd.y);
    clouds *= 0.08 + storm * 0.18;

    vec3 cloudCol = mix(
      vec3(1.0, 0.82, 0.65),
      vec3(0.42, 0.48, 0.56),
      storm
    );

    skyCol = mix(skyCol, mix(skyCol * 0.97, cloudCol, 0.35), clouds);

    float sd = max(dot(rd, sunDir), 0.0);
    skyCol += sunCol * pow(sd, 380.0) * 6.8 * sunGlow;
    skyCol += sunCol * pow(sd, 22.0)  * 0.20 * sunGlow;
    skyCol += sunCol * pow(sd, 5.0)   * 0.09 * sunGlow;

    float sunDisk = smoothstep(0.99925, 0.99995, dot(rd, sunDir));
    skyCol += sunCol * sunDisk * 2.6 * sunGlow;

    float horizonBand = exp(-abs(rd.y) * 24.0);
    skyCol += sunCol * horizonBand * 0.11 * sunGlow;

    float viewSun = max(dot(rd, sunDir), 0.0);
    skyCol += sunCol * pow(viewSun, 3.0) * 0.035 * sunGlow;

    if (moonAmt > 0.04) {
      float md = max(dot(rd, moonDir), 0.0);
      skyCol += vec3(0.88, 0.92, 1.0) * pow(md, 820.0) * 7.4 * moonAmt;
      skyCol += vec3(0.88, 0.92, 1.0) * pow(md, 6.0)   * 0.045 * moonAmt;
    }

    if (night > 0.02) {
      vec2 starUv = rd.xy / max(0.12, rd.z + 1.6);
      starUv *= 140.0;
      float stars = starField(starUv) + starField(starUv * 0.55 + 11.7) * 0.65;
      stars *= smoothstep(0.02, 0.26, rd.y);
      stars *= (1.0 - storm * 0.85);
      skyCol += vec3(0.80, 0.88, 1.0) * stars * night * 0.82;
    }

    float horizonMist = exp(-abs(rd.y) * mix(38.0, 22.0, storm));
    skyCol += fogCol * horizonMist * (0.09 + storm * 0.10);

    skyCol = mix(skyCol, skyCol * vec3(0.91, 0.94, 0.98), storm * 0.22);
  }

  col = mix(col, skyCol, skyMix);

  float hEdge = smoothstep(-0.008, 0.018, rd.y);
  col = mix(fogCol, col, hEdge * 0.25 + 0.75);

  float grain = hash(gl_FragCoord.xy * 0.5 + floor(uT * 12.0)) - 0.5;
  col += grain * 0.006;

  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
`;

const mkShader = (type, src) => {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);

  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    console.error(gl.getShaderInfoLog(s));
    gl.deleteShader(s);
    return null;
  }

  return s;
};

const vert = mkShader(gl.VERTEX_SHADER, vs);
const frag = mkShader(gl.FRAGMENT_SHADER, fs);

if (!vert || !frag) {
  throw new Error("Shader compilation failed");
}

const prog = gl.createProgram();
gl.attachShader(prog, vert);
gl.attachShader(prog, frag);
gl.linkProgram(prog);

if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
  console.error(gl.getProgramInfoLog(prog));
  throw new Error("Program linking failed");
}

gl.useProgram(prog);
gl.disable(gl.DEPTH_TEST);
gl.disable(gl.CULL_FACE);
gl.disable(gl.BLEND);
gl.disable(gl.DITHER);

const buf = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, buf);
gl.bufferData(
  gl.ARRAY_BUFFER,
  new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
  gl.STATIC_DRAW
);

const ap = gl.getAttribLocation(prog, "a");
gl.enableVertexAttribArray(ap);
gl.vertexAttribPointer(ap, 2, gl.FLOAT, false, 0, 0);

const uR = gl.getUniformLocation(prog, "uR");
const uTi = gl.getUniformLocation(prog, "uT");
const uScroll = gl.getUniformLocation(prog, "uS");
const uScene = gl.getUniformLocation(prog, "uSc");
const uBlend = gl.getUniformLocation(prog, "uBl");
const uBg = gl.getUniformLocation(prog, "uBg");

const hexToVec3 = (hex) => {
  const n = parseInt(hex.replace("#", ""), 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
};

const bgColors = {
  dark: "#0a0a0f",
  light: "#eef4ff"
};

const updateBg = (theme) => {
  const [r, g, b] = hexToVec3(bgColors[theme] ?? bgColors.dark);
  gl.uniform3f(uBg, r, g, b);
};

const mq = window.matchMedia("(prefers-color-scheme: dark)");
const getSystemTheme = () => (mq.matches ? "dark" : "light");

let themeOverride = null;
const getActiveTheme = () => themeOverride ?? getSystemTheme();

const applyTheme = (theme) => {
  document.documentElement.setAttribute("data-theme", theme);
  document.documentElement.style.colorScheme = theme;
  updateBg(theme);
};

applyTheme(getActiveTheme());

mq.addEventListener("change", () => {
  if (!themeOverride) applyTheme(getSystemTheme());
});

const themeToggle = document.getElementById("theme_toggle");
if (themeToggle) {
  themeToggle.addEventListener("click", () => {
    themeOverride = getActiveTheme() === "dark" ? "light" : "dark";
    applyTheme(themeOverride);
  });
}

const NAMES = ["DAWN", "MIDDAY", "DUSK", "NIGHT", "STORM"];
const N = NAMES.length;

let maxScroll = 1;
let tgt = 0;
let smooth = 0;
let velocity = 0;

const scrollEase = 0.1;

let qualityScale = 1.0;
const MAX_DPR = 1.5;
const MIN_QUALITY = 0.82;
const MAX_QUALITY = 1.0;

let resizeRAF = 0;
let lastViewportW = 0;
let lastViewportH = 0;

const updateScrollMetrics = () => {
  const vh = lastViewportH || window.innerHeight;
  maxScroll = Math.max(0, document.documentElement.scrollHeight - vh);
  tgt =
    maxScroll > 0 ? Math.min(1, Math.max(0, window.scrollY / maxScroll)) : 0;
};

const resize = () => {
  resizeRAF = 0;

  const vp = window.visualViewport ?? {
    width: window.innerWidth,
    height: window.innerHeight
  };

  const cssW = Math.round(vp.width);
  const cssH = Math.round(vp.height);

  if (!cssW || !cssH) return;

  lastViewportW = cssW;
  lastViewportH = cssH;

  const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
  const renderScale = dpr * qualityScale;

  const pixelW = Math.max(1, Math.round(cssW * renderScale));
  const pixelH = Math.max(1, Math.round(cssH * renderScale));

  canvas.style.width = `${cssW}px`;
  canvas.style.height = `${cssH}px`;

  if (canvas.width !== pixelW || canvas.height !== pixelH) {
    canvas.width = pixelW;
    canvas.height = pixelH;
    gl.viewport(0, 0, pixelW, pixelH);
    gl.uniform2f(uR, pixelW, pixelH);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  updateScrollMetrics();
};

const requestResize = () => {
  if (!resizeRAF) resizeRAF = requestAnimationFrame(resize);
};

resize();
window.addEventListener("resize", requestResize, { passive: true });

if (window.visualViewport) {
  window.visualViewport.addEventListener("resize", requestResize, {
    passive: true
  });
}

window.addEventListener("scroll", updateScrollMetrics, { passive: true });

window.addEventListener("load", updateScrollMetrics, { passive: true });

window.addEventListener(
  "wheel",
  (e) => {
    if (
      e.ctrlKey ||
      e.metaKey ||
      e.target.closest?.('input, textarea, select, [contenteditable="true"]')
    )
      return;

    e.preventDefault();

    const linePx = 16;
    const pagePx = window.innerHeight * 0.9;

    const delta =
      e.deltaMode === 1
        ? e.deltaY * linePx
        : e.deltaMode === 2
        ? e.deltaY * pagePx
        : e.deltaY;

    velocity += delta;
    velocity = Math.max(-520, Math.min(520, velocity));
  },
  { passive: false }
);

const progFill = document.getElementById("prog_fill");
const hudPct = document.getElementById("hud_pct");
const sceneName = document.getElementById("scene_name");
const dots = document.querySelectorAll(".scene-dot");

let lastHUDPct = -1;
let lastHUDScene = -1;

const updateHUD = (s) => {
  const p = Math.round(s * 100);
  const si = Math.min(N - 1, Math.floor(s * N));

  if (p !== lastHUDPct) {
    lastHUDPct = p;
    hudPct && (hudPct.textContent = String(p).padStart(3, "0") + "%");
    progFill && (progFill.style.width = `${p}%`);
  }

  if (si !== lastHUDScene) {
    lastHUDScene = si;
    sceneName && (sceneName.textContent = NAMES[si]);
    dots.forEach((d, i) => d.classList.toggle("active", i === si));
  }
};

const revealEls = [
  ...document.querySelectorAll(
    ".tag, h1, h2, .body-text, .stat-row, .cta, .h-line"
  )
];

for (const el of revealEls) {
  if (el.getBoundingClientRect().top < window.innerHeight * 0.92) {
    el.classList.add("visible");
  }
}

const io = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        io.unobserve(entry.target);
      }
    }
  },
  {
    threshold: 0.1,
    rootMargin: "0px 0px -6% 0px"
  }
);

for (const el of revealEls) {
  io.observe(el);
}

let anchorAnim = null;

const stopAnchorAnim = () => {
  if (anchorAnim) {
    cancelAnimationFrame(anchorAnim);
    anchorAnim = null;
  }
};

const smoothScrollToY = (targetY, duration = 900) => {
  stopAnchorAnim();
  velocity = 0;

  const startY = window.scrollY;
  const diff = targetY - startY;
  const start = performance.now();

  const easeInOutCubic = (t) =>
    t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

  const tick = (now) => {
    const p = Math.min(1, (now - start) / duration);
    const e = easeInOutCubic(p);

    window.scrollTo(0, startY + diff * e);

    if (p < 1) {
      anchorAnim = requestAnimationFrame(tick);
    } else {
      anchorAnim = null;
    }
  };

  anchorAnim = requestAnimationFrame(tick);
};

window.addEventListener("wheel", stopAnchorAnim, { passive: true });
window.addEventListener("touchstart", stopAnchorAnim, { passive: true });
window.addEventListener("mousedown", stopAnchorAnim, { passive: true });
window.addEventListener("keydown", stopAnchorAnim, { passive: true });

document.querySelectorAll('a[href^="#s"]').forEach((a) => {
  a.addEventListener("click", (e) => {
    e.preventDefault();

    const id = a.getAttribute("href");
    const target = document.querySelector(id);
    if (!target) return;

    const y = Math.max(0, Math.min(target.offsetTop, maxScroll));
    smoothScrollToY(y);
  });
});

const t0 = performance.now();
let lastNow = t0;
let fpsAccum = 0;
let fpsFrames = 0;
let lowFpsTime = 0;
let highFpsTime = 0;

const maybeAdjustQuality = (dt) => {
  fpsAccum += dt;
  fpsFrames++;

  if (fpsAccum < 0.75) return;

  const avgDt = fpsAccum / fpsFrames;
  const fps = 1 / avgDt;

  fpsAccum = 0;
  fpsFrames = 0;

  if (fps < 50) {
    lowFpsTime += 0.75;
    highFpsTime = 0;
  } else if (fps > 57) {
    highFpsTime += 0.75;
    lowFpsTime = 0;
  } else {
    lowFpsTime = 0;
    highFpsTime = 0;
  }

  if (lowFpsTime >= 1.5 && qualityScale > MIN_QUALITY) {
    qualityScale = Math.max(MIN_QUALITY, +(qualityScale - 0.06).toFixed(2));
    lowFpsTime = 0;
    requestResize();
  }

  if (highFpsTime >= 3.0 && qualityScale < MAX_QUALITY) {
    qualityScale = Math.min(MAX_QUALITY, +(qualityScale + 0.04).toFixed(2));
    highFpsTime = 0;
    requestResize();
  }
};

const frame = (now) => {
  requestAnimationFrame(frame);

  const dt = Math.min((now - lastNow) / 1000, 0.05);
  lastNow = now;

  maybeAdjustQuality(dt);

  velocity *= Math.pow(0.86, dt * 60);
  if (Math.abs(velocity) < 0.02) velocity = 0;

  if (velocity !== 0) {
    window.scrollBy({
      top: velocity * scrollEase,
      behavior: "auto"
    });
  }

  smooth += (tgt - smooth) * (1 - Math.exp(-dt * 8));

  const raw = smooth * (N - 1);
  const si = Math.min(Math.floor(raw), N - 2);
  const bl = raw - si;

  updateHUD(smooth);

  gl.uniform1f(uTi, (now - t0) / 1000);
  gl.uniform1f(uScroll, smooth);
  gl.uniform1f(uScene, si);
  gl.uniform1f(uBlend, bl);

  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
};

requestAnimationFrame(frame);
