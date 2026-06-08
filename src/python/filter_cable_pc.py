from plyfile import PlyData, PlyElement
import numpy as np
import os
import argparse
import re
import torch


def _resolve_iteration_from_path(input_ply):
    match = re.search(r"iteration_(\d+)", input_ply)
    if match:
        return int(match.group(1))
    return None


def _id_pth_path(iteration, level):
    level_to_file = {
        "s": "small_object_id",
        "m": "middle_object_id",
        "l": "default_object_id",
    }
    base_name = level_to_file[level]
    return f"/data/05_3dgs/output/{base_name}_{iteration}.pth"

def main():
    parser = argparse.ArgumentParser(description="Filter out the background from the Segment-then-Splat point cloud.")
    parser.add_argument("--input_ply", default="/data/05_3dgs/output/point_cloud/iteration_15000/point_cloud.ply", help="Path to raw Point Cloud from STS")
    parser.add_argument("--output_ply", default="/data/05_3dgs/output/point_cloud/iteration_15000/point_cloud_cable.ply", help="Path to save filtered Point Cloud")
    parser.add_argument("--level", default="m", choices=["s", "m", "l"], help="Granularity level: s, m, l")
    parser.add_argument("--object_id", type=int, default=1, help="The target object ID to retain (default is 1 for default segment)")
    args = parser.parse_args()

    if not os.path.exists(args.input_ply):
         # Try automatic resolve of point_cloud.ply if iteration was not 15000
         # i.e., scan directories inside iteration_*
         print(f"Specified point cloud path {args.input_ply} not found. Scanning automatically...")
         base_dir = "/data/05_3dgs/output/point_cloud"
         subdirs = sorted(os.listdir(base_dir)) if os.path.exists(base_dir) else []
         found_ply = None
         for subdir in reversed(subdirs):
             candidate = os.path.join(base_dir, subdir, "point_cloud.ply")
             if os.path.exists(candidate):
                 found_ply = candidate
                 args.input_ply = candidate
                 args.output_ply = os.path.join(base_dir, subdir, "point_cloud_cable.ply")
                 break
         
         if not found_ply:
             print("Error: Could not find any point_cloud.ply in /data/05_3dgs/output/point_cloud/*")
             return

    print(f"Reading point cloud {args.input_ply}...")
    plydata = PlyData.read(args.input_ply)
    vertex_element = plydata['vertex']
    
    data_array = vertex_element.data
    prop_name = f"obj_id_{args.level}"
    labels = None

    label_source_name = prop_name
    if prop_name in [p.name for p in vertex_element.properties]:
        labels = data_array[prop_name]
        print(f"Using object IDs from PLY property '{prop_name}'.")
    else:
        print(f"Warning: Property {prop_name} not found in PLY. Trying STS object-id .pth files...")
        iteration = _resolve_iteration_from_path(args.input_ply)
        if iteration is None:
            print("Error: Could not infer iteration number from input_ply path.")
            return

        pth_path = _id_pth_path(iteration, args.level)
        if not os.path.exists(pth_path):
            print(f"Error: Expected STS object-id file not found: {pth_path}")
            return

        labels_tensor = torch.load(pth_path, map_location="cpu")
        labels = labels_tensor.numpy() if hasattr(labels_tensor, "numpy") else np.asarray(labels_tensor)

        if labels.shape[0] != len(data_array):
            print(
                f"Error: Label count mismatch. pth has {labels.shape[0]} entries, "
                f"but PLY has {len(data_array)} vertices."
            )
            return

        print(f"Using object IDs from {pth_path}.")
        label_source_name = os.path.basename(pth_path)

    # Inspect counts
    unique_vals, counts = np.unique(labels, return_counts=True)
    print(f"Point distribution for '{label_source_name}':")
    for val, count in zip(unique_vals, counts):
        print(f" - Value: {val}, Count: {count} points")

    # Filter out points
    print(f"Filtering points: retaining only those with value={args.object_id}...")
    mask = labels == args.object_id
    filtered_data = data_array[mask]
    
    if len(filtered_data) == 0:
        print(f"Warning: After filtering with requested object_id={args.object_id}, 0 points remain.")

        # STS commonly uses 255 for invalid/unassigned points.
        valid_ids = [int(v) for v in unique_vals.tolist() if int(v) != 255]
        if len(valid_ids) > 0:
            count_map = {int(v): int(c) for v, c in zip(unique_vals, counts)}
            best_id = max(valid_ids, key=lambda vid: count_map.get(vid, 0))
            print(
                f"Requested ID {args.object_id} not present. "
                f"Auto-selecting most frequent valid ID={best_id}."
            )
            mask = labels == best_id
            filtered_data = data_array[mask]
            print(f"Auto-selection retained {len(filtered_data)} points.")
        else:
            print("No valid object IDs found (all labels are 255). Writing original file instead.")
            filtered_data = data_array

    print(f"Retained {len(filtered_data)} / {len(data_array)} points.")

    # Create new PlyData structure and write out
    new_vertex_element = PlyElement.describe(filtered_data, 'vertex')
    
    # Preserve other elements (such as face or normals if they exist)
    other_elements = [el for el in plydata.elements if el.name != 'vertex']
    
    new_elements = [new_vertex_element] + other_elements
    print(f"Writing filtered point cloud to {args.output_ply}...")
    PlyData(new_elements, text=plydata.text, byte_order=plydata.byte_order).write(args.output_ply)
    print("Filtered point cloud saved successfully.")

if __name__ == "__main__":
    main()
