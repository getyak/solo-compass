"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import mapboxgl, { type Map as MapboxMap, Marker } from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";
import { distanceMeters } from "@solo-compass/core";
import type { NearbyResult } from "@/app/api/experiences/nearby/route";
import { categoryEmoji } from "@/lib/category";
import { healthColor, healthLabel } from "@/lib/health";
import { paperCreamStyle } from "@/lib/map-style";
import { clientEnv } from "@/lib/env";

const CHIANG_MAI_CENTER: [number, number] = [98.9853, 18.7883];
const DEFAULT_ZOOM = 14;
/** Refetch threshold — only ask the API again if the user panned this far. */
const REFETCH_PAN_METERS = 500;

interface MapViewProps {
  readonly results: readonly NearbyResult[];
  readonly onSelect: (id: string | null) => void;
  readonly selectedId: string | null;
  /** Called once on map ready and again whenever the user pans >500m. */
  readonly onCenterChange: (center: [number, number]) => void;
}

export function MapView({ results, onSelect, selectedId, onCenterChange }: MapViewProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapboxMap | null>(null);
  const markersRef = useRef<Map<string, Marker>>(new Map());
  const lastReportedCenterRef = useRef<[number, number] | null>(null);
  const [mapReady, setMapReady] = useState(false);

  // Stable refs for handlers used inside map event listeners.
  const onCenterChangeRef = useRef(onCenterChange);
  const onSelectRef = useRef(onSelect);
  useEffect(() => {
    onCenterChangeRef.current = onCenterChange;
  }, [onCenterChange]);
  useEffect(() => {
    onSelectRef.current = onSelect;
  }, [onSelect]);

  const reportCenter = useCallback((center: [number, number]) => {
    const last = lastReportedCenterRef.current;
    if (last && distanceMeters(last, center) < REFETCH_PAN_METERS) return;
    lastReportedCenterRef.current = center;
    onCenterChangeRef.current(center);
  }, []);

  // ─── Mount the map ────────────────────────────────────────────────────────
  useEffect(() => {
    if (mapRef.current || !containerRef.current) return;

    mapboxgl.accessToken = clientEnv.NEXT_PUBLIC_MAPBOX_TOKEN;

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: paperCreamStyle,
      center: CHIANG_MAI_CENTER,
      zoom: DEFAULT_ZOOM,
      attributionControl: true,
    });

    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right");

    map.on("load", () => {
      setMapReady(true);
      const c = map.getCenter();
      reportCenter([c.lng, c.lat]);
    });
    map.on("idle", () => {
      const c = map.getCenter();
      reportCenter([c.lng, c.lat]);
    });

    mapRef.current = map;

    return () => {
      markersRef.current.forEach((m) => m.remove());
      markersRef.current.clear();
      map.remove();
      mapRef.current = null;
    };
  }, [reportCenter]);

  // ─── Geolocate the user once ──────────────────────────────────────────────
  useEffect(() => {
    if (!mapReady) return;
    if (!("geolocation" in navigator)) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const map = mapRef.current;
        if (!map) return;
        map.flyTo({
          center: [pos.coords.longitude, pos.coords.latitude],
          zoom: DEFAULT_ZOOM,
          duration: 1500,
        });
      },
      () => {
        // Permission denied — silently keep the Chiang Mai default. We
        // never gate the map on geolocation.
      },
      { timeout: 5000, maximumAge: 60_000 },
    );
  }, [mapReady]);

  // ─── Render markers when results change ───────────────────────────────────
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();

    for (const result of results) {
      const { experience: exp, health } = result;
      const isSelected = exp.id === selectedId;

      const el = document.createElement("button");
      el.type = "button";
      el.setAttribute("aria-label", `${exp.title}, solo score ${exp.soloScore.overall}, ${healthLabel[health]}`);
      el.className = [
        "relative flex h-11 w-11 items-center justify-center rounded-full",
        "bg-paper-cream/95 shadow-md ring-1 ring-ink-warm/15",
        "text-xl transition-transform hover:scale-110",
        "cursor-pointer focus:outline-none focus:ring-2 focus:ring-deep-teal",
        isSelected ? "scale-125 ring-2 ring-warm-amber" : "",
      ].join(" ");

      // Category emoji
      const emoji = document.createElement("span");
      emoji.textContent = categoryEmoji[exp.category];
      emoji.setAttribute("aria-hidden", "true");
      el.appendChild(emoji);

      // Solo-score badge (top-right)
      const badge = document.createElement("span");
      badge.textContent = String(exp.soloScore.overall);
      badge.setAttribute("aria-hidden", "true");
      badge.className = [
        "absolute -top-1 -right-1 flex h-4 min-w-[1rem] items-center justify-center",
        "rounded-full bg-deep-teal px-1 text-[10px] font-semibold leading-none text-paper-cream",
        "ring-1 ring-paper-cream",
      ].join(" ");
      el.appendChild(badge);

      // Confidence dot (bottom-right)
      const dot = document.createElement("span");
      dot.setAttribute("aria-hidden", "true");
      dot.className = "absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-1 ring-paper-cream";
      dot.style.backgroundColor = healthColor[health];
      el.appendChild(dot);

      el.addEventListener("click", (event) => {
        event.stopPropagation();
        onSelectRef.current(exp.id);
      });

      const [lon, lat] = exp.location.coordinates;
      const marker = new mapboxgl.Marker({ element: el }).setLngLat([lon, lat]).addTo(map);
      markersRef.current.set(exp.id, marker);
    }
  }, [results, mapReady, selectedId]);

  // ─── Click on empty map dismisses ─────────────────────────────────────────
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const handler = () => onSelectRef.current(null);
    map.on("click", handler);
    return () => {
      map.off("click", handler);
    };
  }, [mapReady]);

  return <div ref={containerRef} className="absolute inset-0 h-full w-full" />;
}
