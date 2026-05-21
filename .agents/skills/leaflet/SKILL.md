---
name: leaflet
description: "Expert guidance for Leaflet.js interactive maps, mobile-friendly map layers, GeoJSON rendering, and plugins."
category: gis
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# Leaflet Map Integration

This skill provides comprehensive guidelines for Leaflet.js integration, managing custom tile layers, presenting geospatial vectors (such as cable centerlines), and handling coordinate transformations.

## When to Apply

Use this skill when:
- Creating lightweight, mobile-responsive maps.
- Rendering GeoJSON datasets (e.g., cable alignments or B-Splines).
- Displaying custom markers, popups, and tooltips.
- Implementing custom coordinate systems (like UTM EPSG:25832) using Leaflet projection plugins.

## Core Guidelines

### 1. Mobile Responsiveness and Container Sizing
- Set the map container's CSS dimensions using flexible sizing (e.g., `width: 100%; height: 500px;` or `vh`).
- Call `map.invalidateSize()` if the map is initialized inside a hidden tab or modal that becomes visible later, to force Leaflet to recalculate container bounds.

### 2. Loading and Styling GeoJSON Curves
- Use `L.geoJSON` to import centerline data. 
- Apply standard styling options (weight, color, opacity) to line string layers.
- Bind mouse events (`mouseover`, `mouseout`, `click`) to display attributes like local RMSE or GNSS deviation.

```javascript
L.geoJSON(centerlineData, {
  style: function(feature) {
    return {
      color: "#ff3b30",
      weight: 4,
      opacity: 0.85,
      lineCap: "round"
    };
  },
  onEachFeature: function(feature, layer) {
    if (feature.properties && feature.properties.rmse) {
      layer.bindPopup(`<b>Kabeltrasse:</b> ${feature.properties.name}<br><b>RMSE:</b> ${feature.properties.rmse} cm`);
    }
  }
}).addTo(map);
```

### 3. Custom Projections (UTM EPSG:25832)
Since pipeline data is often computed in UTM coordinates (meters), but Leaflet uses Web Mercator (EPSG:3857) by default:
- Use **Proj4Leaflet** to configure custom projections if rendering raw UTM coordinates directly on the map.
- Alternatively, translate the coordinates to WGS84 (latitude/longitude) on the server/CPU before passing the JSON to Leaflet.

## Troubleshooting & Diagnostics

### Map tile gray squares or partial rendering
- Ensure `map.invalidateSize()` is invoked if container size changes dynamically.
- Check that Leaflet's stylesheet (`leaflet.css`) is imported correctly.

### Memory leaks with multiple layers
- When updating datasets, always remove the old layer instance from the map using `map.removeLayer(oldLayer)` before instantiating a new one.

## Code Review Checklist
- [ ] Container sizes are responsive and `invalidateSize` is bound to layout changes.
- [ ] Leaflet CSS is imported.
- [ ] Old layer instances are removed before adding new datasets.
- [ ] UTM projection parameters (if used) match EPSG:25832 specifications.
