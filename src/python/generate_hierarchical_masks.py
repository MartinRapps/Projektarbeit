import os
import glob
import re
import cv2
import numpy as np


def frame_id_from_path(mask_path: str) -> int:
    stem = os.path.splitext(os.path.basename(mask_path))[0]
    match = re.search(r"frame_(\d+)_obj_001$", stem)
    if match is None:
        raise ValueError(f"Could not parse frame id from {mask_path}")
    return int(match.group(1))


def to_binary_mask(mask: np.ndarray) -> np.ndarray:
    return np.where(mask > 0, 255, 0).astype(np.uint8)

def main():
    print("=== Generating Hierarchical Masks from Existing Flat Masks ===")
    masks_dir = "/data/03_masks"
    
    flat_masks = sorted(glob.glob(os.path.join(masks_dir, "frame_*_obj_001.png")))
    num_masks = len(flat_masks)
    print(f"Found {num_masks} existing flat masks.")
    
    if num_masks == 0:
        print("No flat masks found. Skipping hierarchical generation.")
        return
        
    kernel_size = 5
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kernel_size, kernel_size))
    
    for i, flat_mask_path in enumerate(flat_masks):
        frame_id = frame_id_from_path(flat_mask_path)
        frame_folder = os.path.join(masks_dir, f"frame_{frame_id:05d}")
        os.makedirs(frame_folder, exist_ok=True)

        mask_uint8 = cv2.imread(flat_mask_path, cv2.IMREAD_GRAYSCALE)
            
        if mask_uint8 is None:
            # Fallback to empty black mask (assume 768x1024 or similar)
            mask_uint8 = np.zeros((768, 1024), dtype=np.uint8)
        else:
            mask_uint8 = to_binary_mask(mask_uint8)
            
        # 1. default.png: Original flat mask (context mask)
        mask_default = mask_uint8.copy()
        cv2.imwrite(os.path.join(frame_folder, "default.png"), mask_default)

        # 2. middle.png: Slightly eroded to suppress edge artifacts
        mask_middle = cv2.erode(mask_uint8, kernel, iterations=1)
        cv2.imwrite(os.path.join(frame_folder, "middle.png"), mask_middle)

        # 3. small.png: More conservative core mask
        mask_small = cv2.erode(mask_middle, kernel, iterations=1)
        cv2.imwrite(os.path.join(frame_folder, "small.png"), mask_small)
        
        if i % 10 == 0 or i == num_masks - 1:
            print(f"Processed frame {frame_id:05d} ({i+1}/{num_masks})")
            
    print("Hierarchical mask generation complete.")

if __name__ == "__main__":
    main()
