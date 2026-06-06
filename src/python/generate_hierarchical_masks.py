import os
import glob
import cv2
import numpy as np

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
    
    for i in range(num_masks):
        flat_mask_path = os.path.join(masks_dir, f"frame_{i:05d}_obj_001.png")
        frame_folder = os.path.join(masks_dir, f"frame_{i:05d}")
        os.makedirs(frame_folder, exist_ok=True)
        
        if os.path.exists(flat_mask_path):
            mask_uint8 = cv2.imread(flat_mask_path, cv2.IMREAD_GRAYSCALE)
        else:
            mask_uint8 = None
            
        if mask_uint8 is None:
            # Fallback to empty black mask (assume 768x1024 or similar)
            mask_uint8 = np.zeros((768, 1024), dtype=np.uint8)
            
        # 1. middle.png: Original flat mask
        cv2.imwrite(os.path.join(frame_folder, "middle.png"), mask_uint8)
        
        # 2. small.png: Eroded
        mask_small = cv2.erode(mask_uint8, kernel, iterations=1)
        cv2.imwrite(os.path.join(frame_folder, "small.png"), mask_small)
        
        # 3. default.png: Dilated
        mask_default = cv2.dilate(mask_uint8, kernel, iterations=1)
        cv2.imwrite(os.path.join(frame_folder, "default.png"), mask_default)
        
        if i % 10 == 0 or i == num_masks - 1:
            print(f"Processed frame {i:05d}/{num_masks-1:05d}")
            
    print("Hierarchical mask generation complete.")

if __name__ == "__main__":
    main()
