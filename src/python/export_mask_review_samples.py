import argparse
import os
from typing import List

import cv2
import numpy as np


def pick_sample_indices(num_frames: int) -> List[int]:
    if num_frames <= 1:
        return [0]

    candidates = [
        0,
        max(0, num_frames // 3),
        max(0, (2 * num_frames) // 3),
        num_frames - 1,
    ]

    ordered = []
    for index in candidates:
        if index not in ordered:
            ordered.append(index)
    return ordered


def load_mask(mask_root: str, frame_index: int, mask_name: str, height: int, width: int) -> np.ndarray:
    nested_path = os.path.join(mask_root, f"frame_{frame_index:05d}", f"{mask_name}.png")
    flat_path = os.path.join(mask_root, f"frame_{frame_index:05d}_obj_001.png")

    mask = None
    if os.path.exists(nested_path):
        mask = cv2.imread(nested_path, cv2.IMREAD_GRAYSCALE)
    elif os.path.exists(flat_path):
        mask = cv2.imread(flat_path, cv2.IMREAD_GRAYSCALE)

    if mask is None:
        return np.zeros((height, width), dtype=np.uint8)
    return mask


def draw_overlay(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    overlay = image.copy()
    color_mask = np.zeros_like(image)
    color_mask[:, :, 1] = mask
    overlay = cv2.addWeighted(overlay, 1.0, color_mask, 0.35, 0.0)

    contours, _ = cv2.findContours((mask > 0).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(overlay, contours, -1, (0, 0, 255), 2)
    return overlay


def extract_cutout(image: np.ndarray, mask: np.ndarray, padding: int) -> np.ndarray:
    masked = cv2.bitwise_and(image, image, mask=mask)
    ys, xs = np.where(mask > 0)
    if len(xs) == 0 or len(ys) == 0:
        return masked

    x_min = max(0, int(xs.min()) - padding)
    x_max = min(image.shape[1], int(xs.max()) + padding)
    y_min = max(0, int(ys.min()) - padding)
    y_max = min(image.shape[0], int(ys.max()) + padding)
    return masked[y_min:y_max, x_min:x_max]


def build_panel(image: np.ndarray, overlay: np.ndarray, cutout: np.ndarray) -> np.ndarray:
    target_height = image.shape[0]
    if cutout.shape[0] == 0 or cutout.shape[1] == 0:
        cutout = np.zeros_like(image)
    else:
        scale = target_height / float(cutout.shape[0])
        target_width = max(1, int(round(cutout.shape[1] * scale)))
        cutout = cv2.resize(cutout, (target_width, target_height), interpolation=cv2.INTER_AREA)

    return np.concatenate([image, overlay, cutout], axis=1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export review samples for manual mask edge inspection.")
    parser.add_argument("--frames-dir", default="/data/02_frames", help="Directory with extracted frames")
    parser.add_argument("--masks-dir", default="/data/03_masks", help="Directory with flat and hierarchical masks")
    parser.add_argument("--mask-name", default="middle", choices=["default", "middle", "small"], help="Which hierarchical mask to review")
    parser.add_argument("--output-dir", default="/data/03_masks/_review_samples", help="Where to store review panels")
    parser.add_argument("--padding", type=int, default=24, help="Padding in pixels around the cropped mask region")
    args = parser.parse_args()

    frame_files = sorted(
        name for name in os.listdir(args.frames_dir)
        if name.lower().endswith((".jpg", ".jpeg", ".png"))
    )
    if not frame_files:
        raise FileNotFoundError(f"No frames found in {args.frames_dir}")

    os.makedirs(args.output_dir, exist_ok=True)
    indices = pick_sample_indices(len(frame_files))
    print(f"Exporting mask review samples for indices: {indices}")

    for frame_index in indices:
        frame_path = os.path.join(args.frames_dir, frame_files[frame_index])
        image = cv2.imread(frame_path, cv2.IMREAD_COLOR)
        if image is None:
            print(f"Skipping unreadable frame: {frame_path}")
            continue

        mask = load_mask(args.masks_dir, frame_index, args.mask_name, image.shape[0], image.shape[1])
        overlay = draw_overlay(image, mask)
        cutout = extract_cutout(image, mask, args.padding)
        panel = build_panel(image, overlay, cutout)

        base_name = f"frame_{frame_index:05d}_{args.mask_name}"
        cv2.imwrite(os.path.join(args.output_dir, f"{base_name}_overlay.png"), overlay)
        cv2.imwrite(os.path.join(args.output_dir, f"{base_name}_cutout.png"), cutout)
        cv2.imwrite(os.path.join(args.output_dir, f"{base_name}_panel.png"), panel)

    print(f"Review samples written to {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
