import type { StyleSpecification } from "mapbox-gl";

/**
 * Warm-toned, paper-cream Mapbox style — a quiet base that lets experience
 * markers carry the visual weight. Inline so we don't depend on a Mapbox
 * Studio account for the placeholder build.
 */
export const paperCreamStyle: StyleSpecification = {
  version: 8,
  name: "solo-compass-paper-cream",
  glyphs: "mapbox://fonts/mapbox/{fontstack}/{range}.pbf",
  sources: {
    "carto-voyager": {
      type: "raster",
      tiles: [
        "https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
        "https://b.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
        "https://c.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
      ],
      tileSize: 256,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
    },
  },
  layers: [
    {
      id: "background",
      type: "background",
      paint: { "background-color": "#F5F1E8" },
    },
    {
      id: "carto-voyager",
      type: "raster",
      source: "carto-voyager",
      paint: {
        "raster-opacity": 0.85,
        "raster-saturation": -0.2,
        "raster-contrast": -0.05,
        "raster-hue-rotate": 10,
      },
    },
  ],
};
