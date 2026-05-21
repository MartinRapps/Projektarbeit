---
name: python-best-practices
description: "Expert guidelines for writing clean, PEP 8 compliant, type-hinted, and optimized Python code."
category: quality
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# Python Best Practices

This skill outlines guidelines for writing readable, maintainable, and optimized Python code, particularly for spatial computations, B-Spline interpolations, and distance metrics.

## When to Apply

Use this skill when:
- Writing or refactoring Python scripts for post-processing and coordinate transformations.
- Configuring Conda/Mamba environments in Docker or WSL2.
- Evaluating geometric tolerances (B-Splines, RMSE, Hausdorff distance).
- Performing vectorized transformations on large coordinates or point clouds.

## Core Guidelines

### 1. Code Quality & Formatting
- Adhere to **PEP 8** formatting guidelines. Utilize `ruff` (fast linter and formatter) or `black` for enforcement.
- Use explicit type hints (`typing` module) to improve maintainability and run static type checking with `mypy`.

### 2. Conda/Mamba Environment Management
- Pin exact library versions in `environment.yml` to ensure reproducible builds.
- Clean up package caches (`conda clean -ay`) inside Dockerfiles to reduce image footprint.

### 3. Centerline Evaluation Metris (Splines, RMSE, Hausdorff)
When validating reconstructed centerlines against GNSS reference points:

- **B-Spline Interpolation:** Use `scipy.interpolate.make_lsq_spline` or `splprep` to model the reference points as a smooth 3D parametric curve $S(t) = (x(t), y(t), z(t))$.
- **RMSE Computation:** Compute the distance between each point on the extracted centerline $C_j$ and its orthogonal projection on the reference spline $S(t)$:
  ```python
  import numpy as np
  from scipy.optimize import minimize_scalar

  def point_to_spline_dist(point, spline_tck):
      # Finds the parameter t that minimizes distance
      def dist_sq(t):
          curve_pt = np.array(interpolate.splev(t, spline_tck))
          return np.sum((point - curve_pt) ** 2)
      res = minimize_scalar(dist_sq, bounds=(0, 1), method='bounded')
      return np.sqrt(res.fun)
  ```
- **Hausdorff Distance:** Compute the maximum of the directed Hausdorff distances using `scipy.spatial.distance.directed_hausdorff` to determine the worst-case error (which must be $\le 10$ cm for TenneT compliance):
  ```python
  from scipy.spatial.distance import directed_hausdorff

  def compute_hausdorff(curve_a, curve_b):
      # directed_hausdorff returns (distance, index_a, index_b)
      d_ab = directed_hausdorff(curve_a, curve_b)[0]
      d_ba = directed_hausdorff(curve_b, curve_a)[0]
      return max(d_ab, d_ba)
  ```

### 4. Vectorized Coordinate Transformations (4x4 Matrix)
- Avoid iterating over coordinates with loops. Always use vectorized NumPy operations for transformations:
  ```python
  # Apply 4x4 Transformation Matrix to Nx3 points
  def transform_points(points, matrix):
      # points: shape (N, 3)
      # matrix: shape (4, 4)
      num_points = points.shape[0]
      homogen_points = np.hstack((points, np.ones((num_points, 1))))
      transformed = homogen_points @ matrix.T
      return transformed[:, :3]
  ```

## Troubleshooting & Diagnostics

### NumPy Performance Bottlenecks
- Profile memory usage when processing high-resolution coordinates. Use `memory_profiler` or `cProfile` if CPU usage is high.
- Ensure points are stored in contiguous C-arrays (`np.ascontiguousarray`) for optimal memory access speeds.

## Code Review Checklist
- [ ] Code conforms to PEP 8 standards (verified via Ruff/Pylint).
- [ ] Explicit type annotations are used for all public functions.
- [ ] Parameter estimation (e.g., spline fits) handles edge cases.
- [ ] B-Spline interpolation uses an appropriate smoothing factor.
- [ ] Computational logic avoids nested loops by using vectorized NumPy/SciPy methods.
- [ ] Distance computation handles 3D spaces correctly (e.g., verifying Z-coordinates are included).
