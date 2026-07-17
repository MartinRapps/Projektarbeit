# Scan-to-BIM 3D Reconstruction Pipeline

This repository implements a 5-container Docker-based pipeline for the reconstruction of linear infrastructure (specifically underground cables in construction trenches) for TenneT. The pipeline integrates Meta's SAM 3 for 2D object segmentation, COLMAP for camera poses, Segment-then-Splat (STS) for object-specific 3D Gaussian Splatting, SuGaR for geometric mesh extraction, and DGtal/GDAL for centerline extraction and georeferencing.

---

## Getting Started

### 1. Repository & Data Split
To allow development on local machines and high-performance execution on a GPU-enabled server:
- All source code and Docker configuration files are tracked by Git.
- The `data/` folder is listed in `.gitignore` and is local to the machine running the calculations. You must create this folder locally:
  ```bash
  mkdir -p data/01_raw data/02_frames data/03_masks data/04_sfm data/05_3dgs data/06_mesh data/07_centerline data/08_gis data/09_evaluation
  ```

### 2. Preparing Raw Data

```bash
mkdir -p data/01_raw data/02_frames data/03_masks data/04_sfm data/05_3dgs data/06_mesh data/07_centerline data/08_gis data/09_evaluation
```


Place your starting files in the local `data/` directory:
1. Put the raw 4K drone video in `data/01_raw/video.mp4`.
2. Put the measured GNSS GCP coordinates in `data/01_raw/gcp_coordinates.csv`.

### 3. Execution
Run the master orchestration script on your GPU-enabled machine:
```bash
chmod +x run_pipeline.sh
./run_pipeline.sh
```

If you have already processed the video, extracted SAM 3.1 masks, and computed the COLMAP camera poses, you can bypass the early stages and run the pipeline specifically starting from Segment-then-Splat (STS) onwards:
```bash
chmod +x run_from_sts.sh
./run_from_sts.sh
```

### Object-Only, Mask-Aware SuGaR (Recommended)

For a segmented cable or pipe, an object-only Gaussian cloud must not be
optimized against unmasked full-frame RGB images. The standard pipeline now
keeps `point_cloud.ply` as the full-scene baseline, exports the genuinely
filtered object cloud as `point_cloud_filtered.ply`, and creates
`point_cloud_filtered_opacity999999.ply` as the geometry-oriented SuGaR input.
The latter deliberately overwrites the retained Gaussian opacities with
`alpha=0.999999`; it is an initialization policy for geometry optimization,
not a claim that the object is physically opaque. Use the guided master runner
for the complete workflow:

```bash
chmod +x run_pipeline.sh
./run_pipeline.sh
```

After STS, the runner confirms or edits the filter thresholds and the
high-opacity alpha, then confirms or edits the mask-aware SuGaR settings.
`EXPLAIN` is accepted at each configuration prompt. The current geometry-first
defaults are `min_opacity=0.01`, `black_threshold=0.08`,
`alpha=0.999999`, `dn_consistency` at coarse counter `9001`, 200,000 mesh
vertices, 5,000,000 surface samples, `medium` refinement, zero RGB/UV
dilation, and no consensus crop. The full-scene STS checkpoint is never
overwritten; SuGaR stages a private checkpoint and exports the refined PLY/OBJ
under `data/06_mesh/<export-name>/`.

For a standalone object-only run after STS, prepare the standard input first
and then launch the mask-aware runner:

```bash
./prepare_sugar_input.sh
./run_masked_sugar.sh
```

The runner keeps separate tagged checkpoints below `data/sugar_output/` and
refuses to overwrite an existing tag unless `REPLACE=1` is set deliberately.

The project keeps a pinned SuGaR checkout in `third_party/SuGaR`. The runner
automatically applies `docker-compose.sugar-dev.yml`, which mounts that local
checkout over `/opt/sugar` in the existing SuGaR container. Thus changing the
local fork needs neither a fresh clone nor an image rebuild during development.
After validation, the same tracked source can be baked into the Docker image
for a release build.

For a focused Coarse-mesh extraction from an existing completed run, use:

```bash
SOURCE_RUN_TAG=masked_7000_dn_consistency_medium \
COARSE_MESH_ABLATION_TAG=depth8_v50000 \
MESH_VERTICES=50000 \
POISSON_DEPTH=8 \
./run_coarse_mesh_ablation.sh
```

This does not retrain SuGaR and does not run refinement, UV baking, or crop.
The default source checkpoint is preserved and every ablation requires a new
output tag. To run a new full Coarse optimization but stop immediately after
the resulting Coarse mesh, set `STOP_AFTER_COARSE_MESH=1` on
`run_masked_sugar.sh`.

To crop an already exported textured SuGaR OBJ without retraining, run:

```bash
./run_multiview_crop.sh
```

This uses the existing `sugar-meshing` service and needs no additional
container. The default pass preserves faces with insufficient observations;
review its JSON report before using more aggressive crop options. For an already
dense full-scene mesh, use `CROP_PROFILE=semantic-core` to retain only faces
with semantic support and remove unobserved faces. It writes a separate
`*_semantic_core.obj` result and never replaces the conservative output.

---

## Directory Reference
For a complete breakdown of directories and build caching, refer to the [recommended_structure.md](file:///C:/Users/4567r/.gemini/antigravity-ide/brain/0d83ae5b-3ce6-4d35-b202-67437f7ecc10/recommended_structure.md) design artifact.
