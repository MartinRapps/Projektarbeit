---
name: cpp
description: "Expert guidelines for modern C++ (C++17/20/23), memory management, CMake build systems, and integrating DGtal/CGAL libraries."
category: quality
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# Modern C++ and DGtal Integration

This skill provides coding guidelines and best practices for writing high-performance C++ code, utilizing CMake, and implementing digital geometry algorithms using the **DGtal** (Digital Geometry Tools and Algorithms) library.

## When to Apply

Use this skill when:
- Writing or maintaining C++ code for 3D centerline extraction (e.g., in Container E).
- Interfacing with DGtal data structures (GridCurve, FreemanChain, Cubical Complexes).
- Setting up CMake projects with DGtal, CGAL, Boost, or Eigen.
- Debugging memory leaks, template compile errors, or segmentation faults in geometric code.

## Core Guidelines

### 1. Modern C++ Coding Standards
- **RAII & Memory Safety:** Use smart pointers (`std::unique_ptr`, `std::shared_ptr`) for resource management. Never use raw `new` and `delete` calls.
- **Const Correctness:** Apply `const` to functions and arguments that do not modify state to enable compiler optimizations and prevent side effects.
- **Zero-Cost Abstractions:** Prefer references (`const T&`) instead of copying objects, especially for large matrices (Eigen) or point clouds.

### 2. DGtal Centerline Extraction & Skeletonization
DGtal provides topological thinning algorithms to reduce a 3D digital shape (represented as voxel grids or cubical complexes) to a 1D centerline skeleton while preserving topology.

- **Digital Topology:** Define the digital space (e.g., `Z3i::Space`) and neighborhood connectivity (e.g., $(6, 26)$ or $(26, 6)$ adjacency in 3D).
- **Homotopic Thinning:**
  - Create a cubical complex (`KSpace`) to maintain topology.
  - Use thinning algorithms (like parallel directional collapse or critical kernel thinning) to remove "simple points" without changing the Euler characteristic.
- **DGtal Curve Extraction:**
  - Represent the resulting centerline as a `GridCurve` or graph.
  - Apply curve smoothing or simplification algorithms (such as the Fréchet distance-based simplifier) to filter out digital quantization noise.

```cpp
#include "DGtal/base/Common.h"
#include "DGtal/helpers/StdDefs.h"
#include "DGtal/topology/CCubicalComplex.h"

using namespace DGtal;
using namespace Z3i;

// Basic DGtal setup for 3D digital space
KSpace K;
Domain domain(Point(0,0,0), Point(128,128,128));
K.init(domain.lowerBound(), domain.upperBound(), true);
```

### 3. CMake Integration (DGtal, Boost, Eigen)
- Write modular `CMakeLists.txt` files targeting modern CMake policies (linking targets rather than global variables).
- Link DGtal, Eigen, and Boost targets cleanly:
  ```cmake
  cmake_minimum_required(VERSION 3.16)
  project(CenterlineExtractor)

  find_package(DGtal REQUIRED)
  find_package(Eigen3 REQUIRED)
  find_package(Boost REQUIRED COMPONENTS system)

  add_executable(extractor main.cpp)
  target_link_libraries(extractor PRIVATE DGtal::DGtal Eigen3::Eigen Boost::system)
  ```

## Troubleshooting & Diagnostics

### Long Compile Times & Template Errors
- DGtal uses heavy template meta-programming. To speed up builds, use precompiled headers or structure compilation units to keep headers separated.
- If compile errors are unreadable, inspect template argument types from the bottom up, focusing on space dimension matching (e.g., mixing `Z2i` and `Z3i`).

### Segmentation Faults
- Check for coordinate boundary violations in `KSpace` or `Domain`.
- Ensure all iterator loops on `GridCurve` or digital boundaries terminate correctly.

## Code Review Checklist
- [ ] Smart pointers are preferred over raw pointers.
- [ ] Large geometry structures are passed by reference-to-const.
- [ ] CMake dependencies are linked as target properties.
- [ ] Digital topology connectivity (e.g., 6-connectivity vs 26-connectivity) is explicitly chosen.
- [ ] Digital curves are simplified or smoothed to remove digitization noise.
