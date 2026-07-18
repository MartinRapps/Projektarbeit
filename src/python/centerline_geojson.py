import argparse
import csv
import json
import math
import os
from collections import OrderedDict


def load_paths(input_csv):
    with open(input_csv, 'r', newline='', encoding='utf-8') as input_file:
        reader = csv.DictReader(input_file)
        if reader.fieldnames is None:
            raise ValueError(f"Centerline CSV {input_csv} has no header")
        fields = {field.strip().lower(): field for field in reader.fieldnames}
        for required in ('x', 'y', 'z'):
            if required not in fields:
                raise ValueError(f"Centerline CSV is missing the {required} column")
        branch_field = fields.get('branch_id')
        component_field = fields.get('component_id')
        paths = OrderedDict()
        for row in reader:
            if not any((value or '').strip() for value in row.values()):
                continue
            branch_id = row[branch_field].strip() if branch_field else '0'
            component_id = row[component_field].strip() if component_field else '0'
            point = [float(row[fields[axis]]) for axis in ('x', 'y', 'z')]
            if not all(math.isfinite(value) for value in point):
                raise ValueError("Centerline CSV contains a non-finite coordinate")
            paths.setdefault((branch_id, component_id), []).append(point)
    if not paths:
        raise ValueError(f"Centerline CSV {input_csv} is empty")
    for branch_id, points in paths.items():
        if len(points) < 2:
            raise ValueError(
                f"Branch {branch_id[0]} requires at least two centerline points"
            )
    return paths


def main():
    parser = argparse.ArgumentParser(description='Convert a 3D centerline CSV to GeoJSON.')
    parser.add_argument('--input_csv', required=True)
    parser.add_argument('--output_geojson', required=True)
    parser.add_argument('--srs', default='EPSG:25832')
    args = parser.parse_args()

    paths = load_paths(args.input_csv)
    coordinates_by_path = list(paths.values())
    all_points = [point for coordinates in coordinates_by_path for point in coordinates]
    crs_name = args.srs
    if crs_name.upper().startswith('EPSG:'):
        crs_name = f"urn:ogc:def:crs:EPSG::{crs_name.split(':', 1)[1]}"
    features = []
    for (branch_id, component_id), coordinates in zip(paths.keys(), coordinates_by_path):
        features.append({
            'type': 'Feature',
            'properties': {
                'branch_id': branch_id,
                'component_id': component_id,
                'srs': args.srs,
            },
            'geometry': {'type': 'LineString', 'coordinates': coordinates},
        })
    document = {
        'type': 'FeatureCollection',
        'name': 'centerline',
        'crs': {'type': 'name', 'properties': {'name': crs_name}},
        'bbox': [min(point[0] for point in all_points),
                 min(point[1] for point in all_points),
                 min(point[2] for point in all_points),
                 max(point[0] for point in all_points),
                 max(point[1] for point in all_points),
                 max(point[2] for point in all_points)],
        'features': features,
    }
    output_directory = os.path.dirname(args.output_geojson)
    if output_directory:
        os.makedirs(output_directory, exist_ok=True)
    with open(args.output_geojson, 'w', encoding='utf-8') as output_file:
        json.dump(document, output_file, ensure_ascii=True, indent=2)
        output_file.write('\n')
    if os.path.getsize(args.output_geojson) == 0:
        raise IOError(f"GeoJSON output was not written: {args.output_geojson}")
    print(
        f"Wrote {len(features)} centerline branches and "
        f"{len(all_points)} points to {args.output_geojson}"
    )


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"Error: {error}")