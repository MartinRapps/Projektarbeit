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

---

## Directory Reference
For a complete breakdown of directories and build caching, refer to the [recommended_structure.md](file:///C:/Users/4567r/.gemini/antigravity-ide/brain/0d83ae5b-3ce6-4d35-b202-67437f7ecc10/recommended_structure.md) design artifact.
