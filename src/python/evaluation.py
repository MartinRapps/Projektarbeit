import numpy as np
import scipy.interpolate as interpolate
from scipy.spatial.distance import directed_hausdorff
from scipy.optimize import minimize_scalar

def load_coordinates(csv_path):
    """Loads Nx3 coordinate points from a CSV file."""
    return np.loadtxt(csv_path, delimiter=',', skiprows=1, usecols=(0, 1, 2))

def fit_b_spline(reference_points, smoothing_factor=0.0):
    """Fits a 3D parametric B-Spline to the reference coordinates."""
    # reference_points should be Nx3 array
    x, y, z = reference_points[:, 0], reference_points[:, 1], reference_points[:, 2]
    # Parameterize curve based on chord length
    distances = np.sqrt(np.diff(x)**2 + np.diff(y)**2 + np.diff(z)**2)
    u = np.concatenate(([0], np.cumsum(distances)))
    u /= u[-1]  # Normalize parameter to [0, 1]
    
    tck, u_spline = interpolate.splprep([x, y, z], u=u, s=smoothing_factor)
    return tck

def compute_point_to_spline_dist(point, spline_tck):
    """Computes the shortest distance between a 3D point and the 3D B-Spline."""
    def dist_sq(t):
        curve_pt = np.array(interpolate.splev(t, spline_tck))
        return np.sum((point - curve_pt) ** 2)
    
    # Minimize squared distance inside boundary [0, 1]
    res = minimize_scalar(dist_sq, bounds=(0, 1), method='bounded')
    return np.sqrt(res.fun)

def compute_rmse(extracted_points, spline_tck):
    """Calculates root-mean-square error between extracted points and reference curve."""
    distances = [compute_point_to_spline_dist(p, spline_tck) for p in extracted_points]
    return np.sqrt(np.mean(np.square(distances)))

def compute_hausdorff_distance(extracted_points, reference_points):
    """Calculates the maximum directed Hausdorff distance between two point clouds."""
    # directed_hausdorff returns (distance, index_a, index_b)
    d_ab = directed_hausdorff(extracted_points, reference_points)[0]
    d_ba = directed_hausdorff(reference_points, extracted_points)[0]
    return max(d_ab, d_ba)

if __name__ == "__main__":
    print("Python evaluation script template loaded.")
    # Example usage structure:
    # ref_pts = load_coordinates('data/01_raw/reference_gnss.csv')
    # ext_pts = load_coordinates('data/07_centerline/centerline_extracted.csv')
    # spline = fit_b_spline(ref_pts)
    # rmse = compute_rmse(ext_pts, spline)
    # hd = compute_hausdorff_distance(ext_pts, ref_pts)
    # print(f"RMSE: {rmse:.4f} m, Hausdorff Distance: {hd:.4f} m")
