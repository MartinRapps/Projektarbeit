#!/usr/bin/env python3
"""
Pipeline Status Dashboard Server
Serves the UI and API endpoints for the Scan-to-BIM pipeline.
"""
import os
import json
import mimetypes
import pty
import select
import subprocess
import threading
import queue
import uuid
import signal
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, parse_qs, unquote

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
            {"prompt": "Autopilot-Modus (y/n)", "var": "AUTOPILOT", "type": "confirm"},
            {"prompt": "STS Trainingsiterationen", "var": "ITERATIONS", "default": "7000"},
            {"prompt": "Stage 2 Iterationen", "var": "STAGE2_ITERS"},
            {"prompt": "On-the-fly GPU-Modus", "var": "ON_THE_FLY", "type": "confirm"},
            {"prompt": "Regularisierung (dn_consistency/density/sdf oder EXPLAIN)", "var": "REGULARIZATION"},
            {"prompt": "Refinement-Dauer (short/medium/long oder EXPLAIN)", "var": "REFINEMENT_TIME"},
        ],
    },
    {
        "id": "run_from_colmap",
        "name": "run_from_colmap.sh",
        "description": "F\u00fchrt die Pipeline ab COLMAP SfM aus. \u00dcberspringt die SAM 3.1 Maskengenerierung. N\u00fctzlich wenn die Masken bereits vorhanden sind und nur die 3D-Rekonstruktion wiederholt werden soll.",
        "steps": [
            "COLMAP SfM",
            "Manueller Breakpoint: GCP in CloudCompare",
            "STS Workspace Setup",
            "STS 3DGS Training",
            "Punktwolken-Filterung",
            "SuGaR Meshing",
            "DGtal Centerline",
            "GIS-Export",
        ],
        "inputs": [
            {"prompt": "Autopilot-Modus (y/n)", "var": "AUTOPILOT", "type": "confirm"},
            {"prompt": "STS Trainingsiterationen", "var": "ITERATIONS", "default": "7000"},
        ],
    },
    {
        "id": "run_from_sugar",
        "name": "run_from_sugar.sh",
        "description": "F\u00fchrt nur SuGaR-Meshing und Post-Processing aus. Ben\u00f6tigt einen fertigen STS-Checkpoint (point_cloud.ply). Ideal zum schnellen Testen des Meshing-Schritts.",
        "steps": [
            "SuGaR Coarse-Training + Meshing + Refinement",
            "DGtal Centerline",
            "GIS-Export",
        ],
        "inputs": [
            {"prompt": "Autopilot-Modus (y/n)", "var": "AUTOPILOT", "type": "confirm"},
            {"prompt": "Checkpoint-Iteration", "var": "ITERATIONS", "default": "7000"},
            {"prompt": "Regularisierung (dn_consistency/density/sdf oder EXPLAIN)", "var": "REGULARIZATION"},
            {"prompt": "Refinement-Dauer (short/medium/long oder EXPLAIN)", "var": "REFINEMENT_TIME"},
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
    """Run a shell script inside a pseudo-terminal (PTY).

    A PTY (instead of plain pipes) is essential for interactive scripts:
    'read -p' prompts are written without a trailing newline and bash also
    detects a TTY, so prompts are flushed immediately and appear live in
    the browser terminal. It also lets us forward user answers to stdin.
    """
    q = script_sessions[session_id]["queue"]
    proc = None
    master_fd = None
    try:
        master_fd, slave_fd = pty.openpty()
        proc = subprocess.Popen(
            ["/bin/bash", script_path],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            cwd=PROJECT_ROOT,
            close_fds=True,
            preexec_fn=os.setsid,  # own process group -> we can kill children (docker compose run) too
            env={**os.environ, "TERM": "dumb", "PYTHONUNBUFFERED": "1"},
        )
        os.close(slave_fd)
        with script_sessions_lock:
            script_sessions[session_id]["process"] = proc
            script_sessions[session_id]["master_fd"] = master_fd

        while True:
            with script_sessions_lock:
                cancelled = script_sessions.get(session_id, {}).get("cancel")
            if cancelled:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                except (ProcessLookupError, OSError):
                    pass
                break
            rlist, _, _ = select.select([master_fd], [], [], 0.5)
            if rlist:
                try:
                    data = os.read(master_fd, 8192)
                except OSError:
                    break  # PTY closed (process exited)
                if not data:
                    break
                clean_text = data.decode("utf-8", errors="replace")
                with script_sessions_lock:
                    if session_id in script_sessions:
                        script_sessions[session_id]["log"].append(clean_text)
                q.put(("output", clean_text))
            elif proc.poll() is not None:
                break
        proc.wait()
        q.put(("exit", proc.returncode))
    except Exception as e:
        err_msg = f"\n[FEHLER] {e}\n"
        with script_sessions_lock:
            if session_id in script_sessions:
                script_sessions[session_id]["log"].append(err_msg)
        q.put(("output", err_msg))
        q.put(("exit", -1))
    finally:
        if master_fd is not None:
            try:
                os.close(master_fd)
            except OSError:
                pass
        with script_sessions_lock:
            if session_id in script_sessions:
                script_sessions[session_id]["process"] = None
                script_sessions[session_id]["master_fd"] = None


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

    # First stream any cached historical terminal outputs (allows restoring state on refresh!)
    with script_sessions_lock:
        historical_logs = list(session.get("log", []))
    for log_item in historical_logs:
        payload = json.dumps({"type": "output", "data": log_item})
        if not safe_write(handler, f"data: {payload}\n\n"):
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
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                except (ProcessLookupError, OSError):
                    try:
                        proc.terminate()
                    except Exception:
                        pass
            del script_sessions[session_id]


def send_script_input(session_id, text):
    """Forward user input from the browser to the script's PTY (stdin)."""
    with script_sessions_lock:
        session = script_sessions.get(session_id)
        if not session:
            return False
        proc = session.get("process")
        master_fd = session.get("master_fd")
    if proc and master_fd is not None and proc.poll() is None:
        try:
            os.write(master_fd, (text + "\n").encode())
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
        elif self.path == "/api/script/active":
            # Return active sessions to allow any client reload to seamlessly reconnect!
            active_list = []
            with script_sessions_lock:
                for sid, s in script_sessions.items():
                    proc = s.get("process")
                    running = proc is not None and proc.poll() is None
                    if running:
                        active_list.append({
                            "session_id": sid,
                            "script_id": s["script_id"]
                        })
            self.send_json(active_list)
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
            rel_path = unquote(self.path[len("/api/file/"):])
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
            rel_path = unquote(self.path[len("/api/dir/"):])
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
                    "log": [] # Persistent log of terminal output for page refreshes
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
                            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                        except (ProcessLookupError, OSError):
                            try:
                                proc.terminate()
                            except Exception:
                                pass
            self.send_json({"stopped": True})
        elif self.path == "/api/upload":
            self.handle_upload()
        else:
            self.send_json({"error": "Not found"}, 404)

    # Allowed upload targets (whitelist!) - key is the 'target' form value
    UPLOAD_TARGETS = {
        "matrix_screenshot": {
            "dir": "01_raw",
            "filename": "matrix_screenshot",   # extension appended from upload
            "extensions": [".png", ".jpg", ".jpeg"],
        },
        "raw_video": {
            "dir": "01_raw",
            "filename": None,                    # keep original (sanitized) name
            "extensions": [".mp4", ".mov"],
        },
        "raw_image": {
            "dir": "01_raw",
            "filename": None,
            "extensions": [".png", ".jpg", ".jpeg"],
        },
        "gcp_csv": {
            "dir": "01_raw",
            "filename": None,
            "extensions": [".csv", ".txt"],
        },
        "matrix_txt": {
            "dir": "04_sfm",
            "filename": "matrix",
            "extensions": [".txt"],
        },
    }

    def handle_upload(self):
        """Receive a multipart/form-data upload (drag & drop) and store it
        into the whitelisted data folder. Streams to a temp file so large
        videos do not need to fit in memory twice."""
        try:
            content_type = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in content_type:
                self.send_json({"error": "Erwarte multipart/form-data"}, 400)
                return
            boundary = content_type.split("boundary=")[-1].strip().strip('"')
            if not boundary:
                self.send_json({"error": "Boundary fehlt"}, 400)
                return
            content_len = int(self.headers.get("Content-Length", 0))
            if content_len <= 0:
                self.send_json({"error": "Leerer Upload"}, 400)
                return
            body = self.rfile.read(content_len)

            # --- Parse multipart parts ---
            delim = ("--" + boundary).encode()
            parts = body.split(delim)
            target_key = None
            file_bytes = None
            orig_filename = None
            for part in parts:
                if not part or part in (b"--", b"--\r\n"):
                    continue
                header_end = part.find(b"\r\n\r\n")
                if header_end < 0:
                    continue
                raw_headers = part[:header_end].decode("utf-8", errors="replace")
                content = part[header_end + 4:]
                # Strip trailing CRLF of the part
                if content.endswith(b"\r\n"):
                    content = content[:-2]
                if 'name="target"' in raw_headers:
                    target_key = content.decode("utf-8", errors="replace").strip()
                elif 'name="file"' in raw_headers:
                    file_bytes = content
                    for line in raw_headers.split("\r\n"):
                        if "filename=" in line:
                            orig_filename = line.split("filename=")[-1].strip().strip('"')

            if not target_key or target_key not in self.UPLOAD_TARGETS:
                self.send_json({"error": f"Unbekanntes Upload-Ziel: {target_key}"}, 400)
                return
            if file_bytes is None or not orig_filename:
                self.send_json({"error": "Keine Datei empfangen"}, 400)
                return

            target = self.UPLOAD_TARGETS[target_key]
            ext = os.path.splitext(orig_filename)[1].lower()
            if ext not in target["extensions"]:
                self.send_json({
                    "error": f"Dateityp {ext} nicht erlaubt. Erlaubt: {', '.join(target['extensions'])}"
                }, 400)
                return

            # Sanitize filename: never allow path traversal
            if target["filename"]:
                final_name = target["filename"] + ext
            else:
                final_name = os.path.basename(orig_filename).replace("..", "_")

            dest_dir = os.path.join(DATA_DIR, target["dir"])
            os.makedirs(dest_dir, exist_ok=True)
            dest_path = os.path.join(dest_dir, final_name)
            with open(dest_path, "wb") as f:
                f.write(file_bytes)

            rel = os.path.relpath(dest_path, PROJECT_ROOT)
            self.send_json({
                "saved": True,
                "path": rel,
                "size": len(file_bytes),
                "target": target_key,
            })
        except Exception as e:
            self.send_json({"error": f"Upload fehlgeschlagen: {e}"}, 500)

    def send_json(self, data, status=200):
        safe_send_json(self, data, status)

    def log_message(self, format, *args):
        pass


class ThreadingHTTPServerV(ThreadingMixIn, HTTPServer):
    """Threaded server: each request gets its own thread. Essential because
    SSE terminal streams are long-lived connections - without threading a
    single running script would block all other API calls and uploads."""
    daemon_threads = True
    allow_reuse_address = True  # FIX: instantly reuse port 8080 if restarted!


def main():
    host = "0.0.0.0"
    port = 8080
    print(f" Pipeline Dashboard: http://localhost:{port}")
    print(f" Datenverzeichnis: {DATA_DIR}")
    print(" Drück Ctrl+C zum Beenden")
    server = ThreadingHTTPServerV((host, port), DashboardHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
