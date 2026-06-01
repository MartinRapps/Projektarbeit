import os
import sys
import glob
import gc
import cv2
import argparse
import inspect
from contextlib import nullcontext
from PIL import Image
import torch
import numpy as np
from huggingface_hub import login

# HuggingFace Login für Gated Repositories prüfen
hf_token = os.environ.get("HF_TOKEN")
if hf_token:
    print("HF_TOKEN gefunden. Logge bei HuggingFace ein...")
    login(token=hf_token)
else:
    print("Kein HF_TOKEN als Environment Variable gefunden. Gated Modelle schlagen evtl. fehl.")

# Versuche SAM 3.1 zu importieren (Offizielle API)
try:
    from sam3.model_builder import build_sam3_multiplex_video_predictor
    SAM3_AVAILABLE = True
except ImportError as e:
    print(f"Warning: SAM3 module not found ({e}). Is it installed via pip?")
    SAM3_AVAILABLE = False

def extract_frames(video_path, out_dir):
    print(f"Extracting frames from {video_path} to {out_dir}...")
    max_side = int(os.environ.get("SAM3_FRAME_MAX_SIDE", "960"))
    cap = cv2.VideoCapture(video_path)
    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret: break
        if max_side > 0:
            h, w = frame.shape[:2]
            longest = max(h, w)
            if longest > max_side:
                scale = max_side / float(longest)
                new_w = max(1, int(round(w * scale)))
                new_h = max(1, int(round(h * scale)))
                frame = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)
        frame_name = f"{frame_idx:05d}.jpg"
        cv2.imwrite(os.path.join(out_dir, frame_name), frame)
        frame_idx += 1
    cap.release()
    print(f"Extracted {frame_idx} frames.")
    return frame_idx


def write_mask_frame(frame_idx, frame_data, masks_dir, height, width):
    mask = np.zeros((height, width), dtype=np.uint8)
    if isinstance(frame_data, dict):
        for _, obj_out in frame_data.items():
            if not isinstance(obj_out, dict):
                continue
            if "masks" in obj_out and obj_out["masks"] is not None:
                m_tensor = obj_out["masks"]
                if hasattr(m_tensor, "cpu"):
                    m_tensor = m_tensor.squeeze().cpu().numpy()
                mask = np.maximum(mask, (m_tensor > 0.5).astype(np.uint8) * 255)

    mask_filename = f"frame_{frame_idx:05d}_obj_001.png"
    Image.fromarray(mask).save(os.path.join(masks_dir, mask_filename))

def main():
    parser = argparse.ArgumentParser(description="SAM 3.1 Mask Extraction")
    parser.add_argument("--prompt", type=str, required=True, help="Text prompt for the mask (e.g. 'cable')")
    args = parser.parse_args()

    print(f"=== SAM 3 Extract Masks (Prompt: '{args.prompt}') ===")
    
    raw_dir = "/data/01_raw"
    frames_dir = "/data/02_frames"
    masks_dir = "/data/03_masks"
    
    os.makedirs(frames_dir, exist_ok=True)
    os.makedirs(masks_dir, exist_ok=True)

    video_files = glob.glob(os.path.join(raw_dir, "*.mp4")) + glob.glob(os.path.join(raw_dir, "*.mov"))
    if not video_files:
        print(f"Error: No video found in {raw_dir}")
        sys.exit(1)
        
    video_path = video_files[0]
    num_frames = extract_frames(video_path, frames_dir)
    
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")
    
    if SAM3_AVAILABLE:
        print("Lade SAM 3.1 Checkpoint...")
        from sam3.model_builder import download_ckpt_from_hf
        ckpt_path = download_ckpt_from_hf(version="sam3.1")
        
        print("Initialisiere echtes SAM 3.1 Model ...")
        # Official SAM3.1 multiplex predictor (matches sam3.1_multiplex.pt architecture)
        video_predictor = build_sam3_multiplex_video_predictor(
            checkpoint_path=ckpt_path,
            use_fa3=False,
            use_rope_real=False,
        )
        
        # Dynamically inject memory limitations for 16GB GPUs to prevent OOM
        try:
            # For Sam3VideoPredictorMultiGPU -> model is the actual predictor
            inner_predictor = video_predictor.predictor if hasattr(video_predictor, "predictor") else video_predictor
            # inner_predictor contains model -> SAM3VideoInference
            if hasattr(inner_predictor, "model"):
                inference_model = inner_predictor.model
                if hasattr(inference_model, "clear_non_cond_mem_around_input"):
                    inference_model.clear_non_cond_mem_around_input = True
                if hasattr(inference_model, "tracker") and hasattr(inference_model.tracker, "max_cond_frames_in_attn"):
                    inference_model.tracker.max_cond_frames_in_attn = 2
        except Exception as e:
            print(f"Warning: Could not set memory bounds dynamically: {e}")
        
        # CPU Memory / RAM Protection (Offload to prevent OutOfMemory)
        print(f"Start Session für Ordner: {frames_dir}...")
        
        session_id = None
        start_session_params = inspect.signature(video_predictor.start_session).parameters
        start_session_request = {
            "type": "start_session",
            "resource_path": frames_dir,
            "offload_video_to_cpu": True,
        }
        # Einige SAM3 Builds exposen offload_state_to_cpu in start_session,
        # leiten es aber intern fehlerhaft an model.init_state weiter.
        if "offload_state_to_cpu" in start_session_params:
            print("Hinweis: offload_state_to_cpu wird in diesem Build nicht gesetzt (Kompatibilitaet).")

        # AKTIVIERE BFLOAT16 AUTOCAST UM DEN VRAM BEDARF ZU HALBIEREN
        autocast_ctx = torch.autocast(device_type="cuda", dtype=torch.bfloat16) if device == "cuda" else nullcontext()
        with autocast_ctx:
            try:
                try:
                    response = video_predictor.handle_request(
                        request=start_session_request
                    )
                except TypeError as e:
                    if "offload_state_to_cpu" not in str(e):
                        raise
                    print("Kompatibilitaets-Fallback: entferne offload_state_to_cpu aus model.init_state kwargs und versuche start_session erneut.")
                    if hasattr(video_predictor, "model") and hasattr(video_predictor.model, "init_state"):
                        original_init_state = video_predictor.model.init_state

                        def _init_state_compat(*args, **kwargs):
                            kwargs.pop("offload_state_to_cpu", None)
                            return original_init_state(*args, **kwargs)

                        video_predictor.model.init_state = _init_state_compat
                    response = video_predictor.handle_request(
                        request=start_session_request
                    )
                session_id = response["session_id"]
            
                print(f"Add Prompt '{args.prompt}' auf Frame 0...")
                video_predictor.handle_request(
                    request=dict(
                        type="add_prompt",
                        session_id=session_id,
                        frame_index=0,
                        text=args.prompt,
                    )
                )
            
                print("Propagiere Maske in Chunks durch das Video (Tracking)...")

                first_frame = cv2.imread(os.path.join(frames_dir, "00000.jpg"), cv2.IMREAD_COLOR)
                if first_frame is None:
                    raise RuntimeError("Konnte erste Frame-Datei nicht lesen: /data/02_frames/00000.jpg")
                frame_h, frame_w = first_frame.shape[:2]

                chunk_size = int(os.environ.get("SAM3_MAX_FRAMES_PER_CHUNK", "8"))
                processed_frames = set()

                for start_idx in range(0, num_frames, chunk_size):
                    end_idx = min(start_idx + chunk_size - 1, num_frames - 1)
                    max_track = end_idx - start_idx
                    print(f"Tracking Chunk: {start_idx} bis {end_idx}...")

                    stream = None
                    try:
                        stream = video_predictor.handle_stream_request(
                            request=dict(
                                type="propagate_in_video",
                                session_id=session_id,
                                start_frame_index=start_idx,
                                max_frame_num_to_track=max_track,
                            )
                        )
                        for response_stream in stream:
                            frame_idx = response_stream["frame_index"]
                            write_mask_frame(
                                frame_idx=frame_idx,
                                frame_data=response_stream["outputs"],
                                masks_dir=masks_dir,
                                height=frame_h,
                                width=frame_w,
                            )
                            processed_frames.add(frame_idx)
                            if frame_idx % 8 == 0 and torch.cuda.is_available():
                                torch.cuda.empty_cache()
                            print(f"Tracking: Frame {frame_idx} verarbeitet...")
                    except RuntimeError as e:
                        msg = str(e)
                        if "Tensor sizes:" in msg and "0, 256" in msg and "expanded size" in msg:
                            print("Warnung: Keine trackbaren Objekte fuer den Prompt erkannt. Restliche Frames werden als leere Masken geschrieben.")
                            break
                        raise
                    finally:
                        if stream is not None and hasattr(stream, "close"):
                            stream.close()
                        if torch.cuda.is_available():
                            torch.cuda.empty_cache()
                        gc.collect()

                print("Tracking beendet! Ergänze ggf. fehlende Masken-Frames...")
                for i in range(num_frames):
                    if i not in processed_frames:
                        Image.fromarray(np.zeros((frame_h, frame_w), dtype=np.uint8)).save(
                            os.path.join(masks_dir, f"frame_{i:05d}_obj_001.png")
                        )
            finally:
                if session_id is not None:
                    _ = video_predictor.handle_request(
                        request=dict(
                            type="close_session",
                            session_id=session_id,
                        )
                    )
                    print(f"Session {session_id} geschlossen.")
            
    else:
        print("Mock Mode... SAM 3 nicht gefunden.")
        
    print(f"Masken in {masks_dir} geschrieben.")

if __name__ == "__main__":
    try:
        main()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(0)
    except Exception:
        raise
