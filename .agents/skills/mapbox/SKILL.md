---
name: mapbox
description: "Expert guidance for Mapbox GL JS integration, GeoJSON data visualization, styling GIS layers, and 3D terrain rendering."
category: gis
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# Mapbox GIS Integration

This skill provides expert guidelines for implementing Mapbox GL JS maps, styling geospatial datasets, importing and displaying GeoJSON centerlines, and integrating 3D visualizations in coordinate spaces aligned with TenneT's UTM coordinate systems.

## When to Apply

Use this skill when:
- Visualizing pipeline outputs (centerlines, meshes) in Mapbox GL JS.
- Displaying GeoJSON overlays of cable Scheitelachse/centerlines.
- Configuring 3D terrain mesh rendering or custom WebGL layers.
- Aligning Three.js 3D models within a Mapbox canvas.
- Managing projection transformations between Web Mercator and UTM (EPSG:25832).

## Core Guidelines

### 1. Map Initialization and Life Cycle
- Always load the Mapbox GL JS CSS file to avoid layout breakage.
- Initialize the map inside container elements and clean up using `map.remove()` on component unmount to prevent WebGL context leaks.
- Prefer vector tiles and geojson clustering (`cluster: true`) when displaying large datasets to optimize rendering.

### 2. GeoJSON Centerline Visualizations
- Register datasets using `map.addSource` with `type: 'geojson'` and update coordinates dynamically using `source.setData(geojson)`.
- Use a dedicated `line` layer for centerlines and set appropriate paint properties:
  - `line-color`: Choose high-contrast colors.
  - `line-width`: Set visible widths, potentially dependent on zoom levels (`zoom` expressions).
  - `line-join` & `line-cap`: Use `round` to smooth sharp coordinate transitions.

```javascript
map.addSource('cable-centerline', {
  type: 'geojson',
  data: centerlineGeoJson
});

map.addLayer({
  id: 'centerline-layer',
  type: 'line',
  source: 'cable-centerline',
  layout: {
    'line-join': 'round',
    'line-cap': 'round'
  },
  paint: {
    'line-color': '#ff3b30',
    'line-width': ['interpolate', ['linear'], ['zoom'], 10, 2, 18, 6]
  }
});
```

### 3. Mapbox GL JS & Three.js 3D Custom Layer Integration
To render 3D meshes (such as the BIM `.obj` output from SuGaR) in Mapbox GL JS:
- Convert the local geographic origin (anchor point of the 3D model) to Mercator units:
  ```javascript
  const modelOrigin = [11.581981, 48.135125]; // Longitude, Latitude
  const modelAltitude = 0;
  const modelAsMercator = mapboxgl.MercatorCoordinate.fromLngLat(modelOrigin, modelAltitude);
  ```
- Scale the Three.js model according to the Mercator unit scale using `modelAsMercator.meterInMercatorCoordinateUnits()`.
- Multiply Mapbox's projection matrix by the model's transformation matrix to update the Three.js camera:
  ```javascript
  render: function(gl, matrix) {
    const projectionMatrix = new THREE.Matrix4().fromArray(matrix);
    const transformMatrix = new THREE.Matrix4()
      .makeTranslation(modelAsMercator.x, modelAsMercator.y, modelAsMercator.z)
      .scale(new THREE.Vector3(scale, -scale, scale)); // Note Y-axis flip depending on orientation

    this.camera.projectionMatrix = projectionMatrix.multiply(transformMatrix);
    this.renderer.state.reset();
    this.renderer.render(this.scene, this.camera);
    this.map.triggerRepaint();
  }
  ```

## Troubleshooting & Diagnostics

### Blank map or missing WebGL context
- **Check browser compatibility:** Run `mapboxgl.supported()` before initializing.
- **Resource management:** Ensure you are not creating multiple map instances without removing the old ones, exceeding the maximum WebGL context limit (usually 8-16).

### 3D Model misplaced or floating
- Ensure the scale is computed using `meterInMercatorCoordinateUnits()`. A scale value of `1.0` in Web Mercator represents the entire earth width, which will make the model invisible or infinitely large.
- Verify the coordinate reference system. Reconstructed coordinates in UTM (EPSG:25832) must be translated into WGS84 (Longitude/Latitude) before feeding them to `fromLngLat`.

## Code Review Checklist
- [ ] Map instance is properly disposed of on component destruction.
- [ ] CSS files are loaded dynamically or statically.
- [ ] Large GeoJSON datasets are clustered or simplified.
- [ ] 3D models use correct scale factors matching Mercator units.
- [ ] Axis orientations (Y-up vs Z-up) are explicitly handled during projection conversion.
