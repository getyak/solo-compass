"use client";

/**
 * HeroCanvas — editorial Three.js atmosphere behind Hero.
 * Doc: WEB_LANDING_DESIGN.md §0 ("编辑感, 不 SaaS 感")
 *
 * Three layered elements, all VERY slow — closer to weather
 * than to animation. Aim: feel like sunrise light through
 * warm curtains + a slow-turning compass rose behind the fold.
 *
 *   1. WarmAuroraPlane — a plane with a hand-rolled shader
 *      that mixes bg-warm/sun-gold/accent-soft into a
 *      slowly-drifting caustic. This is the "weather".
 *
 *   2. CompassRings — 3 concentric circles (torus geometry)
 *      rotating on independent axes at fraction-of-degree /
 *      second speeds. This is the brand hint (a compass).
 *
 *   3. Dust — 220 subtle particles of amber, drifting slowly
 *      upward. Not "snow" — think dust motes in a sunbeam.
 *
 * Nothing here can be clicked or focused. It is decoration.
 * `prefers-reduced-motion` disables all animation and locks
 * to a still frame. DPR is capped at 1.5.
 */

import { Canvas, useFrame } from "@react-three/fiber";
import { useMemo, useRef, useEffect, useState } from "react";
import * as THREE from "three";

const CT = {
  bgWarm: new THREE.Color("#FAF8F6"),
  sunGoldSoft: new THREE.Color("#F5E9D2"),
  sunGold: new THREE.Color("#C9A677"),
  omenGold: new THREE.Color("#B8925C"),
  accent: new THREE.Color("#5D3000"),
  accentSoft: new THREE.Color("#FBF1E4"),
};

/* ---------- Aurora plane (custom shader) ---------- */

const auroraVertex = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const auroraFragment = /* glsl */ `
  varying vec2 vUv;
  uniform float uTime;
  uniform vec3 uColorA;
  uniform vec3 uColorB;
  uniform vec3 uColorC;
  uniform vec3 uColorBg;

  // simplex-ish noise (cheap, editorial — we don't need fidelity)
  float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
  float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
  }

  float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.55;
    for (int i = 0; i < 4; i++) {
      v += amp * noise(p);
      p *= 2.02;
      amp *= 0.5;
    }
    return v;
  }

  void main() {
    // Drift slowly to the right — like curtains catching morning light.
    vec2 p = vUv * vec2(1.6, 1.0);
    p.x += uTime * 0.012;
    p.y -= uTime * 0.006;

    float n1 = fbm(p * 1.3);
    float n2 = fbm((p + vec2(4.2, 1.7)) * 2.1);

    // Blend three warm colors into the bg. Never fully overrides the base
    // — max mix ~0.55 so the page background stays legible.
    vec3 c = uColorBg;
    c = mix(c, uColorA, smoothstep(0.35, 0.75, n1) * 0.45);
    c = mix(c, uColorB, smoothstep(0.45, 0.85, n2) * 0.28);
    c = mix(c, uColorC, smoothstep(0.55, 0.95, n1 * n2) * 0.18);

    // Vignette down toward top-left (Hero text lives there — we want
    // the atmosphere to gather bottom-right, behind the phone).
    float vig = smoothstep(0.0, 1.4, distance(vUv, vec2(0.85, 0.35)));
    c = mix(c, uColorBg, vig * 0.55);

    gl_FragColor = vec4(c, 1.0);
  }
`;

function WarmAuroraPlane({ paused }: { paused: boolean }) {
  const matRef = useRef<THREE.ShaderMaterial>(null);

  const uniforms = useMemo(
    () => ({
      uTime: { value: 0 },
      uColorA: { value: CT.sunGoldSoft },
      uColorB: { value: CT.sunGold },
      uColorC: { value: CT.omenGold },
      uColorBg: { value: CT.bgWarm },
    }),
    [],
  );

  useFrame((_, dt) => {
    if (paused) return;
    const u = matRef.current?.uniforms.uTime;
    if (u) u.value += dt;
  });

  return (
    <mesh position={[0, 0, -2]}>
      <planeGeometry args={[20, 12, 1, 1]} />
      <shaderMaterial
        ref={matRef}
        vertexShader={auroraVertex}
        fragmentShader={auroraFragment}
        uniforms={uniforms}
        transparent={false}
        depthWrite={false}
      />
    </mesh>
  );
}

/* ---------- Compass rings — 3 concentric tori ---------- */

function CompassRings({ paused }: { paused: boolean }) {
  const g = useRef<THREE.Group>(null);
  const r1 = useRef<THREE.Mesh>(null);
  const r2 = useRef<THREE.Mesh>(null);
  const r3 = useRef<THREE.Mesh>(null);

  useFrame((_, dt) => {
    if (paused) return;
    if (r1.current) r1.current.rotation.z += dt * 0.015;
    if (r2.current) r2.current.rotation.z -= dt * 0.008;
    if (r3.current) r3.current.rotation.z += dt * 0.005;
    if (g.current) {
      g.current.rotation.x = Math.sin(performance.now() * 0.00005) * 0.05;
      g.current.rotation.y = Math.cos(performance.now() * 0.00004) * 0.04;
    }
  });

  return (
    <group ref={g} position={[3.5, -0.5, -0.5]}>
      <mesh ref={r1}>
        <torusGeometry args={[3.6, 0.006, 12, 128]} />
        <meshBasicMaterial color={CT.accent} transparent opacity={0.14} />
      </mesh>
      <mesh ref={r2}>
        <torusGeometry args={[2.85, 0.005, 12, 128]} />
        <meshBasicMaterial color={CT.omenGold} transparent opacity={0.16} />
      </mesh>
      <mesh ref={r3}>
        <torusGeometry args={[2.1, 0.004, 12, 128]} />
        <meshBasicMaterial color={CT.sunGold} transparent opacity={0.2} />
      </mesh>
      {/* Compass needle — a single subtle line */}
      <mesh rotation={[0, 0, 0]}>
        <planeGeometry args={[0.015, 2.4]} />
        <meshBasicMaterial color={CT.accent} transparent opacity={0.22} />
      </mesh>
    </group>
  );
}

/* ---------- Dust motes ---------- */

function Dust({ paused, count = 220 }: { paused: boolean; count?: number }) {
  const pointsRef = useRef<THREE.Points>(null);

  const { positions, seeds } = useMemo(() => {
    const positions = new Float32Array(count * 3);
    const seeds = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      positions[i * 3 + 0] = (Math.random() - 0.5) * 14;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 8;
      positions[i * 3 + 2] = -0.4 + Math.random() * 0.6;
      seeds[i] = Math.random();
    }
    return { positions, seeds };
  }, [count]);

  useFrame((_, dt) => {
    if (paused) return;
    const points = pointsRef.current;
    if (!points) return;
    const arr = (points.geometry.attributes.position as THREE.BufferAttribute).array as Float32Array;
    for (let i = 0; i < count; i++) {
      const yIdx = i * 3 + 1;
      const xIdx = i * 3;
      const seed = seeds[i] ?? 0;
      const y = arr[yIdx] ?? 0;
      const x = arr[xIdx] ?? 0;
      arr[yIdx] = y + dt * (0.03 + seed * 0.02);
      arr[xIdx] = x + Math.sin(performance.now() * 0.0002 + seed * 6.28) * dt * 0.02;
      if ((arr[yIdx] ?? 0) > 4.5) arr[yIdx] = -4.5;
    }
    (points.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
  });

  return (
    <points ref={pointsRef}>
      <bufferGeometry>
        <bufferAttribute attach="attributes-position" args={[positions, 3]} />
      </bufferGeometry>
      <pointsMaterial
        color={CT.sunGold}
        size={0.028}
        transparent
        opacity={0.55}
        sizeAttenuation
        depthWrite={false}
      />
    </points>
  );
}

/* ---------- Scene ---------- */

export function HeroCanvas() {
  const [reduced, setReduced] = useState(false);
  const [inView, setInView] = useState(true);
  const [supported, setSupported] = useState(true);
  const [isMobile, setIsMobile] = useState(false);
  // Delay mount until the browser is idle — LCP text renders first,
  // atmosphere fades in when there are cycles to spare. This is the
  // single largest LCP win we can make while keeping the canvas.
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const on = (e: MediaQueryListEvent) => setReduced(e.matches);
    mq.addEventListener("change", on);

    const mqMobile = window.matchMedia("(max-width: 767px)");
    setIsMobile(mqMobile.matches);
    const onMobile = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mqMobile.addEventListener("change", onMobile);

    const io = new IntersectionObserver(
      ([e]) => setInView(!!e?.isIntersecting),
      { threshold: 0.02 },
    );
    const el = document.getElementById("hero-canvas-anchor");
    if (el) io.observe(el);

    try {
      const c = document.createElement("canvas");
      const gl = c.getContext("webgl2") || c.getContext("webgl");
      if (!gl) setSupported(false);
    } catch {
      setSupported(false);
    }

    // Idle-mount. requestIdleCallback where available, setTimeout fallback.
    type IdleWindow = Window & {
      requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number;
      cancelIdleCallback?: (id: number) => void;
    };
    const w = window as IdleWindow;
    let idleId: number | null = null;
    let timeoutId: number | null = null;
    if (typeof w.requestIdleCallback === "function") {
      idleId = w.requestIdleCallback(() => setReady(true), { timeout: 1200 });
    } else {
      timeoutId = window.setTimeout(() => setReady(true), 700);
    }

    return () => {
      mq.removeEventListener("change", on);
      mqMobile.removeEventListener("change", onMobile);
      io.disconnect();
      if (idleId !== null && typeof w.cancelIdleCallback === "function") {
        w.cancelIdleCallback(idleId);
      }
      if (timeoutId !== null) window.clearTimeout(timeoutId);
    };
  }, []);

  if (!supported) return null;

  const paused = reduced || !inView;
  // Mobile: softer, less busy — dust down 100, opacity down to 0.55.
  // Editorial rule: on the small screen, atmosphere should recede so
  // the H1 (which is already 56px there, not 96px) carries the frame.
  const dustCount = isMobile ? 120 : 220;
  const layerOpacity = isMobile ? 0.55 : 1;

  return (
    <div
      id="hero-canvas-anchor"
      className="pointer-events-none absolute inset-0 -z-10"
      style={{
        opacity: ready ? layerOpacity : 0,
        transition: "opacity 640ms cubic-bezier(0, 0, 0.2, 1)",
      }}
      aria-hidden
    >
      {ready && <Canvas
        gl={{
          antialias: true,
          alpha: false,
          powerPreference: "low-power",
          preserveDrawingBuffer: false,
        }}
        dpr={[1, isMobile ? 1.25 : 1.5]}
        camera={{ position: [0, 0, 4], fov: 55 }}
        style={{ background: "transparent" }}
        frameloop={paused ? "demand" : "always"}
      >
        <WarmAuroraPlane paused={paused} />
        <CompassRings paused={paused} />
        <Dust paused={paused} count={dustCount} />
      </Canvas>}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-24"
        style={{
          background: "linear-gradient(to bottom, var(--bg-warm) 0%, transparent 100%)",
        }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-40"
        style={{
          background: "linear-gradient(to top, var(--bg-warm) 0%, transparent 100%)",
        }}
      />
    </div>
  );
}
