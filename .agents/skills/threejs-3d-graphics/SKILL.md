---
name: threejs-3d-graphics
description: "Expert guidelines for Three.js 3D web graphics, WebGL rendering, loading OBJ/PLY meshes, and scene optimization."
category: design
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# Three.js 3D Web Graphics

This skill provides comprehensive guidelines for setting up high-performance Three.js scenes, importing 3D models (such as OBJ/PLY meshes), and mitigating floating-point precision limitations in large geographic spaces (e.g., UTM coordinates).

## When to Apply

Use this skill when:
- Visualizing reconstructed 3D cable meshes (SuGaR output) or centerlines.
- Loading `.obj` or `.ply` models.
- Addressing rendering anomalies (shaking, clipping, z-fighting).
- Building browser-based 3D applications or dashboards.

## Core Guidelines

### 1. Solving Floating-Point Precision Jittering (Large Coordinates)
WebGL/GPUs use 32-bit floating-point numbers (`Float32Array`). When UTM coordinates exceed $10^5$ (e.g., $X=32624102$, $Y=5410204$), the GPU lacks the bits to represent millimeters. This causes "vertex jittering" or shaking when zooming.

- **CPU-Side Geometry Rebase (Local Origin):**
  - Choose a local anchor point (e.g., the first GCP or the bounding box center of the cable: $X_{\text{anchor}}, Y_{\text{anchor}}, Z_{\text{anchor}}$).
  - Subtract this anchor point from all vertex coordinates *before* uploading to the GPU (CPU-side).
  - Store the geometry around $(0,0,0)$.
- **Relative Positioning:**
  - Place your mesh in the scene at $(0,0,0)$.
  - Keep track of the offset to reconstruct global coordinates for user queries (e.g., coordinates under mouse clicks).

```javascript
// Example: Translating vertex data relative to an anchor point on the CPU
function rebaseVertices(vertices, anchor) {
  const rebased = new Float32Array(vertices.length);
  for (let i = 0; i < vertices.length; i += 3) {
    rebased[i] = vertices[i] - anchor.x;
    rebased[i + 1] = vertices[i + 1] - anchor.y;
    rebased[i + 2] = vertices[i + 2] - anchor.z;
  }
  return rebased;
}
```

### 2. Loading OBJ and PLY meshes (SuGaR & Poisson output)
- Use `PLYLoader` (for `.ply` surface models) or `OBJLoader` (for `.obj` meshes).
- After loading, compute the bounding box and center to ensure correct positioning.
- Assign appropriate materials (e.g., `THREE.MeshStandardMaterial` for realistic shading or `THREE.MeshBasicMaterial` for vertex-colored point clouds).

```javascript
import { PLYLoader } from 'three/examples/jsm/loaders/PLYLoader.js';

const loader = new PLYLoader();
loader.load('path/to/reconstructed_mesh.ply', (geometry) => {
  geometry.computeVertexNormals();
  const material = new THREE.MeshStandardMaterial({ 
    color: 0x8a8a8a, 
    roughness: 0.4,
    metalness: 0.2
  });
  const mesh = new THREE.Mesh(geometry, material);
  scene.add(mesh);
});
```

### 3. Rendering Optimization & Memory Management
- **Dispose of resources:** JavaScript garbage collection does not automatically clean up WebGL memory. Always manually dispose of geometries, materials, and textures when removing objects.
  ```javascript
  function removeMesh(mesh) {
    scene.remove(mesh);
    if (mesh.geometry) mesh.geometry.dispose();
    if (mesh.material) {
      if (Array.isArray(mesh.material)) {
        mesh.material.forEach(m => m.dispose());
      } else {
        mesh.material.dispose();
      }
    }
  }
  ```
- **Manage Draw Calls:** Merge static meshes using `BufferGeometryUtils.mergeGeometries` or use `InstancedMesh` for repeated objects.
- **Set Camera Near/Far Clipping:** Keep the ratio between `near` and `far` planes as small as possible (e.g., `near = 0.1`, `far = 1000`) to prevent Z-fighting.

## Troubleshooting & Diagnostics

### Geometry shakes or disappears when rotating
- Ensure coordinates are rebased to a local origin $(0,0,0)$.
- Check that the camera target is close to the local origin.

### Black screen or no visibility
- Verify that your lights (`THREE.AmbientLight` and `THREE.DirectionalLight`) are added to the scene.
- Check that the camera is positioned far enough away and looking at the object using `camera.lookAt(mesh.position)`.
- Ensure the model's bounding box is computed and scale is appropriate.

## Code Review Checklist
- [ ] Large coordinates (UTM) are rebased to a local origin $(0,0,0)$ on the CPU.
- [ ] Geometry, material, and texture allocations are cleaned up using `.dispose()`.
- [ ] Camera near/far clipping ratio is optimized.
- [ ] Mesh normals are computed (`computeVertexNormals()`) for correct lighting calculations.
