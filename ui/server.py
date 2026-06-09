#!/usr/bin/env python3
"""
Pipeline Status Dashboard Server
Serves the UI and API endpoints for the Scan-to-BIM pipeline.
"""
import os
import json
import mimetypes
import subprocess
import threading
import queue
import uuid
import signal
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from datetime import datetime

DATA_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data'))
PUBLIC_DIR = os.path.join(os.path.dirname(__file__), 'public')
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def safe_write(self, data):
    try:
        if isinstance(data, str):
            data = data.encode()
        self.wfile.write(data)
        self.wfile.flush()
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass


def safe_send_json(self, data, status=200):
    try:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass


SCRIPTS_INFO = [
    {
        "id": "run_pipeline",
        "name": "run_pipeline.sh",
        "description": "F\u00fchrt die gesamte Scan-to-BIM Pipeline von der GCP-Vorbereitung bis zum GIS-Export aus. Inkludiert SAM 3.1 Segmentierung, COLMAP SfM, STS 3DGS Training, SuGaR Meshing und Post-Processing.",
        "steps": [
            "GCP-Vorbereitung",
            "SAM 3.1 Tracking & Masken",
            "COLMAP SfM",
            "Manueller Breakpoint: GCP in CloudCompare",
            "STS 3DGS Training",
            "SuGaR Meshing",
            "DGtal Centerline",
            "GIS-Export",
        ],
        "inputs": [
            {"prompt": "HuggingFace Token f\u00fcr SAM 3.1", "var": "HF_TOKEN", "type": "password"},
            {"prompt": "Text-Prompt (z.B. 'cable', 'pipe')", "var": "TEXT_PROMPT"},
            {"prompt": "Video verwenden / komprimieren", "var": "VIDEO_CONFIG", "type": "confirm"},
            {"prompt": "STS Trainingsiterationen", "var": "ITERATIONS", "default": "7000"},
            {"prompt": "Stage 2 Iterationen", "var": "STAGE2_ITERS"},
            {"prompt": "On-the-fly GPU-Modus", "var": "ON_THE_FLY", "type": "confirm"},
        ],
    },
    {
        "id": "run_from_sts",
        "name": "run_from_sts.sh",
        "description": "F\u00fchrt die Pipeline ab dem STS-Training aus. \u00dcberspringt SAM 3.1 und COLMAP, startet direkt bei der 3DGS-Rekonstruktion. N\u00fctzlich wenn Masken und SfM bereits vorhanden sind.",
        "steps": [
            "STS Workspace Setup",
            "STS 3DGS Training",
            "Punktwolken-Filterung",
            "SuGaR Meshing",
            "DGtal Centerline",
            "GIS-Export",
        ],
        "inputs": [
            {"prompt": "STS Trainingsiterationen", "var": "ITERATIONS", "default": "7000"},
            {"prompt": "Stage 2 Iterationen", "var": "STAGE2_ITERS"},
            {"prompt": "On-the-fly GPU-Modus", "var": "ON_THE_FLY", "type": "confirm"},
        ],
    },
    {
        "id": "run_sam3",
        "name": "run_sam3.sh",
        "description": "F\u00fchrt nur das SAM 3.1 Video-Preprocessing aus: Frame-Extraktion und Objekt-Maskierung mit dem SAM 3.1 Video Predictor.",
        "steps": [
            "HF Token Pr\u00fcfung",
            "Video-Eingabe Konfiguration",
            "SAM 3.1 Tracking",
            "Masken-Extraktion",
        ],
        "inputs": [
            {"prompt": "HuggingFace Token f\u00fcr SAM 3.1", "var": "HF_TOKEN", "type": "password"},
            {"prompt": "Text-Prompt (z.B. 'cable', 'pipe')", "var": "TEXT_PROMPT"},
            {"prompt": "Video verwenden / komprimieren", "var": "VIDEO_CONFIG", "type": "confirm"},
        ],
    },
    {
        "id": "clean_data",
        "name": "clean_data_interactive.sh",
        "description": "Interaktive Bereinigung von abgeleiteten Pipeline-Daten. L\u00f6scht ausgew\u00e4hlte Ausgabeordner (Frames, Masken, SfM, STS, Mesh, GIS, Evaluation) und optional den HF-Cache.",
        "steps": [
            "SAM3-Daten l\u00f6schen (02-03)",
            "COLMAP-Daten l\u00f6schen (04)",
            "STS-Daten l\u00f6schen (05)",
            "Mesh/GIS/Evaluation l\u00f6schen (06-09)",
            "Komprimiertes Video l\u00f6schen",
            "HF Cache l\u00f6schen (optional)",
        ],
        "inputs": [
            {"prompt": "SAM 3 Ausgabe zur\u00fccksetzen?", "var": "DELETE_SAM3", "type": "confirm"},
            {"prompt": "COLMAP zur\u00fccksetzen?", "var": "DELETE_COLMAP", "type": "confirm"},
            {"prompt": "STS/3DGS zur\u00fccksetzen?", "var": "DELETE_STS", "type": "confirm"},
            {"prompt": "Mesh/Postprocess l\u00f6schen?", "var": "DELETE_LATE", "type": "confirm"},
            {"prompt": "Komprimiertes Video l\u00f6schen?", "var": "DELETE_COMPRESSED", "type": "confirm"},
            {"prompt": "HF Cache l\u00f6schen?", "var": "DELETE_CACHE", "type": "confirm"},
            {"prompt": "Best\u00e4tigung (DELETE eingeben)", "var": "CONFIRM", "type": "text"},
        ],
    },
]

# Script execution sessions
script_sessions = {}
script_sessions_lock = threading.Lock()


def run_script_thread(script_path, session_id):
    q = script_sessions[session_id]["queue"]
    proc = None
    try:
        proc = subprocess.Popen(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.PIPE,
            text=True,
            bufsize=1,
            cwd=PROJECT_ROOT,
            preexec_fn=lambda: signal.signal(signal.SIGPIPE, signal.SIG_DFL),
        )
        with script_sessions_lock:
            script_sessions[session_id]["process"] = proc
        for line in iter(proc.stdout.readline, ""):
            with script_sessions_lock:
                if script_sessions.get(session_id, {}).get("cancel"):
                    proc.terminate()
                    break
            q.put(("output", line))
        proc.wait()
        q.put(("exit", proc.returncode))
    except Exception as e:
        q.put(("output", f"\n[FEHLER] {e}\n"))
        q.put(("exit", -1))
    finally:
        with script_sessions_lock:
            if session_id in script_sessions:
                script_sessions[session_id]["process"] = None


def handle_script_serve(handler, session_id):
    with script_sessions_lock:
        session = script_sessions.get(session_id)
    if not session:
        handler.send_json({"error": "Session not found"}, 404)
        return
    try:
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Cache-Control", "no-cache")
        handler.send_header("Connection", "keep-alive")
        handler.send_header("Access-Control-Allow-Origin", "*")
        handler.end_headers()
    except (ConnectionResetError, BrokenPipeError, OSError):
        return
    q = session["queue"]
    while True:
        try:
            msg_type, data = q.get(timeout=2)
            payload = json.dumps({"type": msg_type, "data": data})
            safe_write(handler, f"data: {payload}\n\n")
            if msg_type == "exit":
                break
        except queue.Empty:
            safe_write(handler, "data: {\"type\":\"heartbeat\"}\n\n")
    cleanup_script_session(session_id)


def cleanup_script_session(session_id):
    with script_sessions_lock:
        if session_id in script_sessions:
            proc = script_sessions[session_id].get("process")
            if proc:
                try:
                    proc.terminate()
                except Exception:
                    pass
            del script_sessions[session_id]


def send_script_input(session_id, text):
    with script_sessions_lock:
        session = script_sessions.get(session_id)
        if not session:
            return False
        proc = session.get("process")
    if proc and proc.stdin and proc.poll() is None:
        try:
            proc.stdin.write(text + "\n")
            proc.stdin.flush()
            return True
        except OSError:
            return False
    return False


PIPELINE_STEPS = [
    {
        "id": "raw",
        "label": "01 Rohdaten (Video/GNSS)",
        "dir": "01_raw",
        "container": "Host",
        "scripts": ["run_pipeline.sh", "prepare_gcp.py"],
        "outputs": ["*.mp4", "*.mov", "*.jpg"],
    },
    {
        "id": "frames",
        "label": "02 Frame-Extraktion",
        "dir": "02_frames",
        "container": "Container A (SAM 3)",
        "scripts": ["extract_masks_notebook_flow.py", "extract_masks.py"],
        "outputs": ["*.jpg", "*.png"],
    },
    {
        "id": "masks",
        "label": "03 SAM 3 Masken",
        "dir": "03_masks",
        "container": "Container A (SAM 3)",
        "scripts": ["extract_masks_notebook_flow.py"],
        "outputs": ["*mask*.png", "*_obj_*.png"],
    },
    {
        "id": "sfm",
        "label": "04 COLMAP SfM",
        "dir": "04_sfm",
        "container": "Container B (COLMAP)",
        "scripts": ["run_sfm.sh"],
        "outputs": ["points3D.ply", "database.db", "sparse/"],
    },
    {
        "id": "sts",
        "label": "05 STS 3DGS Training",
        "dir": "05_3dgs",
        "container": "Container C (STS)",
        "scripts": ["prep_sts_scene.py", "train.py", "filter_cable_pc.py"],
        "outputs": ["output/point_cloud/*.ply", "output/*.pth"],
    },
    {
        "id": "mesh",
        "label": "06 SuGaR Meshing",
        "dir": "06_mesh",
        "container": "Container D (SuGaR)",
        "scripts": ["extract_mesh.py"],
        "outputs": ["*.ply", "*.obj"],
    },
    {
        "id": "centerline",
        "label": "07 DGtal Centerline",
        "dir": "07_centerline",
        "container": "Container E (Post-Processing)",
        "scripts": ["postprocess.sh"],
        "outputs": ["*.csv", "*.ply"],
    },
    {
        "id": "gis",
        "label": "08 GIS-Export",
        "dir": "08_gis",
        "container": "Container E (Post-Processing)",
        "scripts": ["postprocess.sh", "transform_centerline.py"],
        "outputs": ["*.geojson", "*.csv", "*.shp"],
    },
    {
        "id": "eval",
        "label": "09 Evaluation",
        "dir": "09_evaluation",
        "container": "Host",
        "scripts": ["evaluation.py"],
        "outputs": ["*.json", "*.csv", "*.png", "*.pdf"],
    },
]


def scan_dir(dirpath, patterns=None):
    if not os.path.isdir(dirpath):
        return []
    entries = []
    for fname in sorted(os.listdir(dirpath)):
        fpath = os.path.join(dirpath, fname)
        rel = os.path.relpath(fpath, os.path.dirname(DATA_DIR))
        if os.path.islink(fpath) and not os.path.exists(fpath):
            continue
        try:
            stat = os.stat(fpath)
        except (FileNotFoundError, OSError):
            continue
        is_dir = os.path.isdir(fpath) and not os.path.islink(fpath)
        size = stat.st_size if not is_dir else 0
        mtime = datetime.fromtimestamp(stat.st_mtime).isoformat()
        entry = {
            "name": fname,
            "path": rel,
            "size": size,
            "mtime": mtime,
            "is_dir": is_dir,
        }
        if is_dir:
            children = scan_dir(fpath)
            if children:
                entry["children"] = children
        entries.append(entry)
    return entries


def get_step_info(step):
    dirpath = os.path.join(DATA_DIR, step["dir"])
    exists = os.path.isdir(dirpath)
    files = scan_dir(dirpath) if exists else []
    nonempty = len(files) > 0

    ply_files = []
    img_files = []
    video_files = []
    obj_files = []
    pth_files = []
    csv_files = []
    json_files = []
    geojson_files = []

    def collect(fs):
        for f in fs:
            if f.get("children"):
                collect(f["children"])
            name = f["name"].lower()
            if name.endswith(".ply"):
                ply_files.append(f)
            elif name.endswith((".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")):
                img_files.append(f)
            elif name.endswith((".mp4", ".mov", ".avi", ".webm")):
                video_files.append(f)
            elif name.endswith(".obj"):
                obj_files.append(f)
            elif name.endswith(".pth"):
                pth_files.append(f)
            elif name.endswith(".csv"):
                csv_files.append(f)
            elif name.endswith(".json"):
                json_files.append(f)
            elif name.endswith(".geojson"):
                geojson_files.append(f)

    collect(files)

    preview = {}
    if img_files:
        preview["images"] = img_files[:min(len(img_files), 6)]
    if video_files:
        preview["video"] = video_files[0]
    if ply_files:
        preview["ply"] = ply_files[0]
    if obj_files:
        preview["obj"] = obj_files[0]
    if pth_files:
        preview["checkpoints"] = [f for f in pth_files]
    if csv_files:
        preview["csv"] = csv_files[0]
    if geojson_files:
        preview["geojson"] = geojson_files[0]
    if json_files:
        preview["json"] = json_files[-1] if len(json_files) > 1 else json_files[0]

    return {
        "id": step["id"],
        "label": step["label"],
        "dir": step["dir"],
        "container": step["container"],
        "scripts": step["scripts"],
        "exists": exists,
        "nonempty": nonempty,
        "file_count": len(files) if exists else 0,
        "files": files if nonempty else [],
        "preview": preview,
        "total_file_count": sum(1 for _ in walk_files(dirpath)) if exists else 0,
    }


def walk_files(dirpath):
    for root, dirs, files in os.walk(dirpath):
        for f in files:
            yield os.path.join(root, f)


class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC_DIR, **kwargs)

    def do_GET(self):
        if self.path == "/api/steps":
            self.send_json([get_step_info(s) for s in PIPELINE_STEPS])
        elif self.path == "/api/scripts":
            self.send_json(SCRIPTS_INFO)
        elif self.path.startswith("/api/script/stream/"):
            session_id = self.path.split("/")[-1]
            handle_script_serve(self, session_id)
        elif self.path.startswith("/api/script/status/"):
            session_id = self.path.split("/")[-1]
            with script_sessions_lock:
                session = script_sessions.get(session_id)
            if session:
                proc = session.get("process")
                running = proc is not None and proc.poll() is None
                self.send_json({"running": running, "session_id": session_id})
            else:
                self.send_json({"running": False, "session_id": session_id})
        elif self.path.startswith("/api/file/"):
            rel_path = self.path[len("/api/file/"):]
            abs_path = os.path.abspath(os.path.join(DATA_DIR, "..", rel_path))
            if os.path.isfile(abs_path):
                try:
                    self.send_response(200)
                    mime, _ = mimetypes.guess_type(abs_path)
                    self.send_header("Content-Type", mime or "application/octet-stream")
                    self.send_header("Content-Length", os.path.getsize(abs_path))
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.end_headers()
                    with open(abs_path, "rb") as f:
                        safe_write(self, f.read())
                except (ConnectionResetError, BrokenPipeError, OSError):
                    pass
            else:
                self.send_json({"error": "File not found"}, 404)
        elif self.path.startswith("/api/dir/"):
            rel_path = self.path[len("/api/dir/"):]
            abs_path = os.path.abspath(os.path.join(DATA_DIR, rel_path))
            if os.path.isdir(abs_path):
                self.send_json(scan_dir(abs_path))
            else:
                self.send_json({"error": "Directory not found"}, 404)
        elif self.path == "/api/info":
            self.send_json({
                "project": "KI-gestützte 3D-Rekonstruktion linearer Infrastruktur",
                "pipeline": "Scan-to-BIM mit SAM 3 + Gaussian Splatting",
                "data_dir": DATA_DIR,
            })
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == "/api/script/run":
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len).decode()) if content_len else {}
            script_id = body.get("script_id", "")
            script_info = next((s for s in SCRIPTS_INFO if s["id"] == script_id), None)
            if not script_info:
                self.send_json({"error": "Script not found"}, 404)
                return
            script_path = os.path.join(PROJECT_ROOT, script_info["name"])
            if not os.path.isfile(script_path):
                self.send_json({"error": f"Script file not found: {script_path}"}, 404)
                return
            session_id = str(uuid.uuid4())
            with script_sessions_lock:
                script_sessions[session_id] = {
                    "queue": queue.Queue(),
                    "process": None,
                    "cancel": False,
                    "script_id": script_id,
                }
            t = threading.Thread(target=run_script_thread, args=(script_path, session_id), daemon=True)
            t.start()
            self.send_json({"session_id": session_id, "script_id": script_id})
        elif self.path.startswith("/api/script/input/"):
            session_id = self.path.split("/")[-1]
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len).decode()) if content_len else {}
            text = body.get("input", "")
            ok = send_script_input(session_id, text)
            self.send_json({"sent": ok})
        elif self.path == "/api/script/stop":
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len).decode()) if content_len else {}
            session_id = body.get("session_id", "")
            with script_sessions_lock:
                if session_id in script_sessions:
                    script_sessions[session_id]["cancel"] = True
                    proc = script_sessions[session_id].get("process")
                    if proc:
                        try:
                            proc.terminate()
                        except Exception:
                            pass
            self.send_json({"stopped": True})
        else:
            self.send_json({"error": "Not found"}, 404)

    def send_json(self, data, status=200):
        safe_send_json(self, data, status)

    def log_message(self, format, *args):
        pass


def main():
    host = "0.0.0.0"
    port = 8080
    print(f" Pipeline Dashboard: http://localhost:{port}")
    print(f" Datenverzeichnis: {DATA_DIR}")
    print(" Drück Ctrl+C zum Beenden")
    server = HTTPServer((host, port), DashboardHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
