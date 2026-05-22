import os
import numpy as np
import pandas as pd

def load_matrix(matrix_path):
    """Loads a 4x4 transformation matrix from a text file."""
    # CloudCompare outputs the matrix as 4 lines of space-separated floats
    matrix = np.loadtxt(matrix_path)
    if matrix.shape != (4, 4):
        raise ValueError(f"Matrix in {matrix_path} must be of shape 4x4, got {matrix.shape}")
    return matrix

def load_anchor(anchor_path):
    """Loads the 3D anchor coordinates from a text file."""
    with open(anchor_path, 'r') as f:
        content = f.read().strip()
    parts = content.split(',')
    if len(parts) != 3:
        raise ValueError(f"Anchor in {anchor_path} must contain 3 comma-separated coordinates")
    return np.array([float(p) for p in parts])

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Transform local centerline coordinates to global UTM using 4x4 matrix and anchor.")
    parser.add_argument("--input_csv", default="/data/07_centerline/centerline_local.csv", help="Path to local centerline CSV")
    parser.add_argument("--matrix", default="/data/04_sfm/matrix.txt", help="Path to CloudCompare 4x4 matrix")
    parser.add_argument("--anchor_txt", default="/data/01_raw/anchor.txt", help="Path to anchor coordinates text file")
    parser.add_argument("--output_csv", default="/data/07_centerline/centerline_utm.csv", help="Path to output georeferenced CSV")
    
    args = parser.parse_args()
    
    # Check inputs
    if not os.path.exists(args.input_csv):
        print(f"Error: Local centerline file {args.input_csv} not found.")
        return
    if not os.path.exists(args.matrix):
        print(f"Error: Transformation matrix {args.matrix} not found. Please complete the CloudCompare step.")
        return
    if not os.path.exists(args.anchor_txt):
        print(f"Error: Anchor file {args.anchor_txt} not found. Did you run the GCP preparation script?")
        return
        
    print(f"Loading local centerline from {args.input_csv}...")
    # Assume CSV has x, y, z columns or is comma-separated floats
    try:
        df = pd.read_csv(args.input_csv)
        # Verify columns or load as raw array if no header
        if 'x' in df.columns and 'y' in df.columns and 'z' in df.columns:
            points_local = df[['x', 'y', 'z']].values
        else:
            points_local = df.values[:, :3]  # Take first 3 columns
    except Exception as e:
        print(f"Error reading CSV: {e}. Trying raw numpy loading...")
        points_local = np.loadtxt(args.input_csv, delimiter=',')
        
    print(f"Loaded {len(points_local)} centerline points.")
    
    # Load 4x4 matrix and anchor
    try:
        matrix = load_matrix(args.matrix)
        print("Loaded 4x4 transformation matrix:\n", matrix)
    except Exception as e:
        print(f"Error loading matrix: {e}")
        return
        
    try:
        anchor = load_anchor(args.anchor_txt)
        print(f"Loaded anchor point coordinates: East={anchor[0]}, North={anchor[1]}, Height={anchor[2]}")
    except Exception as e:
        print(f"Error loading anchor: {e}")
        return
        
    # Apply 4x4 transformation matrix
    # P_relative = R * P_local + T
    # Convert points to homogeneous coordinates [X, Y, Z, 1]
    num_points = len(points_local)
    homogeneous_points = np.hstack((points_local, np.ones((num_points, 1))))
    
    # Matrix multiplication: shape (N, 4) x (4, 4)^T -> (N, 4)
    transformed_homogeneous = homogeneous_points @ matrix.T
    points_relative = transformed_homogeneous[:, :3]
    
    # Add anchor to shift back to global UTM coordinates
    points_global = points_relative + anchor
    
    # Save output
    df_output = pd.DataFrame(points_global, columns=['x', 'y', 'z'])
    df_output.to_csv(args.output_csv, index=False)
    
    print(f"Successfully georeferenced centerline and saved to {args.output_csv}")

if __name__ == '__main__':
    main()
