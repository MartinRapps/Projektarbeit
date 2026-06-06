import os
import glob
import shutil
import cv2
import numpy as np

def clean_and_create_dir(path):
    if os.path.islink(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)
    os.makedirs(path, exist_ok=True)

def main():
    print("=== Preparing Segment-then-Splat (STS) Scene Structure ===")
    
    scene_root = "/data/05_3dgs"
    frames_dir = "/data/02_frames"
    masks_dir = "/data/03_masks"
    sfm_dir = "/data/04_sfm"
    
    # 1. Clean and setup directories
    print("Setting up directory structure under /data/05_3dgs...")
    os.makedirs(scene_root, exist_ok=True)
    
    # Images symlink/copy (using a symlink is fast and works inside Docker)
    images_link = os.path.join(scene_root, "images")
    if os.path.islink(images_link):
        os.unlink(images_link)
    elif os.path.exists(images_link):
        shutil.rmtree(images_link)
    
    os.symlink(frames_dir, images_link)
    print(f"Created symlink to input images: {images_link} -> {frames_dir}")
    
    # Sparse COLMAP model directory
    sparse_target_parent = os.path.join(scene_root, "sparse")
    os.makedirs(sparse_target_parent, exist_ok=True)
    
    sparse_link = os.path.join(sparse_target_parent, "0")
    if os.path.islink(sparse_link):
        os.unlink(sparse_link)
    elif os.path.exists(sparse_link):
        shutil.rmtree(sparse_link)
        
    sfm_sparse_src = os.path.join(sfm_dir, "sparse/0")
    if not os.path.exists(sfm_sparse_src):
        # Fallback to sparse if mapper output folder name is not '0'
        sfm_sparse_src = os.path.join(sfm_dir, "sparse")
        
    shutil.copytree(sfm_sparse_src, sparse_link)
    print(f"Copied sparse model to workspace: {sparse_link} From {sfm_sparse_src}")
    
    # Setup masks directories (we assume object ID 000 for our tracked segment)
    mask_levels = ["default", "middle", "small"]
    for lvl in mask_levels:
        lvl_dir = os.path.join(scene_root, f"multiview_masks_{lvl}")
        clean_and_create_dir(lvl_dir)
        os.makedirs(os.path.join(lvl_dir, "000"), exist_ok=True)

    # 2. Get and sort frames
    frames = sorted(glob.glob(os.path.join(frames_dir, "*.jpg")) + 
                    glob.glob(os.path.join(frames_dir, "*.jpeg")) + 
                    glob.glob(os.path.join(frames_dir, "*.png")))
    num_frames = len(frames)
    print(f"Found {num_frames} frames in {frames_dir}.")
    
    if num_frames == 0:
        print("Error: No frames found to process.")
        return

    # 3. Process train/test split files
    train_txt_path = os.path.join(scene_root, "train.txt")
    test_txt_path = os.path.join(scene_root, "test.txt")
    
    train_frames = []
    test_frames = []
    
    for idx, frame_path in enumerate(frames):
        basename = os.path.basename(frame_path)
        if num_frames < 20:
            # Short video sequence: put everything in train and test
            train_frames.append(basename)
            test_frames.append(basename)
        else:
            # Hold out every 10th frame for validation
            if idx % 10 == 0:
                test_frames.append(basename)
            else:
                train_frames.append(basename)
                
    with open(train_txt_path, "w") as f:
        f.write("\n".join(train_frames) + "\n")
        
    with open(test_txt_path, "w") as f:
        f.write("\n".join(test_frames) + "\n")
        
    print(f"Split completed: written {len(train_frames)} to train.txt, {len(test_frames)} to test.txt")

    # 4. Copy and resize/format multi-level masks
    print("Formatting hierarchical masks for STS loader requirements...")
    for idx, frame_path in enumerate(frames):
        frame_name = os.path.basename(frame_path)
        image_stem = os.path.splitext(frame_name)[0]
        
        # Frame index corresponds to the subdirectory name structure (padded to 5 digits)
        frame_subdir = os.path.join(masks_dir, f"frame_{idx:05d}")
        
        # Build paths for each level
        for lvl in mask_levels:
            src_png = os.path.join(frame_subdir, f"{lvl}.png")
            dst_jpg = os.path.join(scene_root, f"multiview_masks_{lvl}", "000", f"{image_stem}.jpg")
            
            if os.path.exists(src_png):
                # Read mask array and save as JPG grayscale to match hardcoded requirements
                mask = cv2.imread(src_png, cv2.IMREAD_GRAYSCALE)
                if mask is not None:
                    # Write out as .jpg
                    cv2.imwrite(dst_jpg, mask)
                else:
                    print(f"Warning: Mask {src_png} could not be parsed by OpenCV.")
            else:
                # If a mask doesn't exist, build a black mask matching frame dimensions
                frame_img = cv2.imread(frame_path)
                h, w = frame_img.shape[:2] if frame_img is not None else (768, 1024)
                black_mask = np.zeros((h, w), dtype=np.uint8)
                cv2.imwrite(dst_jpg, black_mask)
                
    print("Hierarchical mask mapping complete. Prepared directory shapes: ")
    print(f" - /data/05_3dgs/multiview_masks_default/000/")
    print(f" - /data/05_3dgs/multiview_masks_middle/000/")
    print(f" - /data/05_3dgs/multiview_masks_small/000/")
    print("Successfully structured active reconstruction workspace.")

if __name__ == "__main__":
    main()
