"use client";

import { useEffect, useRef, useState } from "react";
import mapboxgl, { type Map as MapboxMap, Marker } from "mapbox-gl";
import "mapbox-gl/dist/mapbox-gl.css";
import type { Experience } from "@solo-compass/core";
import { categoryEmoji } from "@/lib/category";
import { paperCreamStyle } from "@/lib/map-style";

const CHIANG_MAI_CENTER: [number, number] = [98.9853, 18.7883];
const DEFAULT_ZOOM = 14;

interface MapViewProps {
  readonly experiences: readonly Experience[];
  readonly onSelectExperience: (exp: Experience | null) => void;
  readonly selectedId: string | null;
}

export function MapView({ experiences, onSelectExperience, selectedId }: MapViewProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapboxMap | null>(null);
  const markersRef = useRef<Map<string, Marker>>(new Map());
  const [mapReady, setMapReady] = useState(false);

  useEffect(() => {
    if (mapRef.current || !containerRef.current) return;

    const token = process.env.NEXT_PUBLIC_MAPBOX_TOKEN ?? "pk.placeholder_token";
    mapboxgl.accessToken = token;

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: paperCreamStyle,
      center: CHIANG_MAI_CENTER,
      zoom: DEFAULT_ZOOM,
      attributionControl: true,
    });

    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right");

    map.on("load", () => setMapReady(true));

    mapRef.current = map;

    return () => {
      markersRef.current.forEach((m) => m.remove());
      markersRef.current.clear();
      map.remove();
      mapRef.current = null;
    };
  }, []);

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
        // user declined or failed — stay on Chiang Mai default.
      },
      { timeout: 5000, maximumAge: 60_000 },
    );
  }, [mapReady]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;

    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();

    for (const exp of experiences) {
      const el = document.createElement("button");
      el.type = "button";
      el.setAttribute("aria-label", exp.title);
      el.className = [
        "flex h-10 w-10 items-center justify-center rounded-full",
        "bg-paper-cream/95 shadow-md ring-1 ring-ink-warm/10",
        "text-xl transition-transform hover:scale-110",
        "cursor-pointer focus:outline-none focus:ring-2 focus:ring-deep-teal",
        exp.id === selectedId ? "scale-125 ring-2 ring-warm-amber" : "",
      ].join(" ");
      el.textContent = categoryEmoji[exp.category];
      el.addEventListener("click", (event) => {
        event.stopPropagation();
        onSelectExperience(exp);
      });

      const [lon, lat] = exp.location.coordinates;
      const marker = new mapboxgl.Marker({ element: el }).setLngLat([lon, lat]).addTo(map);
      markersRef.current.set(exp.id, marker);
    }
  }, [experiences, mapReady, selectedId, onSelectExperience]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const handler = () => onSelectExperience(null);
    map.on("click", handler);
    return () => {
      map.off("click", handler);
    };
  }, [mapReady, onSelectExperience]);

  return <div ref={containerRef} className="absolute inset-0 h-full w-full" />;
}
