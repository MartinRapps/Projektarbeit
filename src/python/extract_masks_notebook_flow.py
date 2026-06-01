import argparse
import glob
import os
import shutil
import sys
from contextlib import nullcontext

import cv2
import numpy as np
import torch
from huggingface_hub import login
from PIL import Image


def find_input_video(raw_dir: str) -> str:
    video_files = sorted(glob.glob(os.path.join(raw_dir, "*.mp4")) + glob.glob(os.path.join(raw_dir, "*.mov")))
    if not video_files:
        raise FileNotFoundError(f"No input video found in {raw_dir}")
    return video_files[0]


def extract_frames(video_path: str, out_dir: str, max_side: int) -> int:
    os.makedirs(out_dir, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if max_side > 0:
            h, w = frame.shape[:2]
            longest = max(h, w)
            if longest > max_side:
                scale = max_side / float(longest)
                nw = max(1, int(round(w * scale)))
                nh = max(1, int(round(h * scale)))
                frame = cv2.resize(frame, (nw, nh), interpolation=cv2.INTER_AREA)

        cv2.imwrite(os.path.join(out_dir, f"{frame_idx:05d}.jpg"), frame)
        frame_idx += 1

    cap.release()
    return frame_idx


def write_mask_from_outputs(frame_idx: int, outputs: dict, masks_dir: str, height: int, width: int) -> int:
    merged = np.zeros((height, width), dtype=np.uint8)

    if isinstance(outputs, dict):
        for _, obj_out in outputs.items():
            if not isinstance(obj_out, dict):
                continue
            m = obj_out.get("masks")
            if m is None:
                continue
            if hasattr(m, "cpu"):
                m = m.squeeze().cpu().numpy()
            cur = (m > 0.5).astype(np.uint8) * 255
            merged = np.maximum(merged, cur)

    Image.fromarray(merged).save(os.path.join(masks_dir, f"frame_{frame_idx:05d}_obj_001.png"))
    return int(np.count_nonzero(merged) > 0)


def clear_png_masks(dir_path: str) -> None:
    if not os.path.isdir(dir_path):
        return
    for name in os.listdir(dir_path):
        if name.endswith(".png") and name.startswith("frame_"):
            os.remove(os.path.join(dir_path, name))


def sanitize_prompt_for_dir(name: str) -> str:
    clean = "".join(ch.lower() if ch.isalnum() else "_" for ch in name.strip())
    while "__" in clean:
        clean = clean.replace("__", "_")
    clean = clean.strip("_")
    return clean or "prompt"


def patch_offload_state_bug_if_needed(predictor):
    if not hasattr(predictor, "model") or not hasattr(predictor.model, "init_state"):
        return

    original_init_state = predictor.model.init_state

    def _init_state_compat(*args, **kwargs):
        kwargs.pop("offload_state_to_cpu", None)
        return original_init_state(*args, **kwargs)

    predictor.model.init_state = _init_state_compat


def main() -> int:
    parser = argparse.ArgumentParser(description="SAM3.1 notebook-style video mask extraction")
    parser.add_argument("--prompt", required=True, type=str)
    parser.add_argument("--raw-dir", default="/data/01_raw", type=str)
    parser.add_argument("--frames-dir", default="/data/02_frames", type=str)
    parser.add_argument("--masks-dir", default="/data/03_masks", type=str)
    parser.add_argument("--frame-max-side", default=int(os.environ.get("SAM3_FRAME_MAX_SIDE", "960")), type=int)
    parser.add_argument("--threshold", default=float(os.environ.get("SAM3_DETECTION_THRESHOLD", "0.5")), type=float)
    args = parser.parse_args()

    hf_token = os.environ.get("HF_TOKEN")
    if hf_token:
        print("HF_TOKEN gefunden. Logge bei HuggingFace ein...")
        login(token=hf_token)

    from sam3.model_builder import build_sam3_multiplex_video_predictor, download_ckpt_from_hf

    os.makedirs(args.frames_dir, exist_ok=True)
    os.makedirs(args.masks_dir, exist_ok=True)

    video_path = find_input_video(args.raw_dir)
    print(f"Input video: {video_path}")

    num_frames = extract_frames(video_path, args.frames_dir, args.frame_max_side)
    if num_frames <= 0:
        raise RuntimeError("No frames extracted from input video")

    first = cv2.imread(os.path.join(args.frames_dir, "00000.jpg"), cv2.IMREAD_COLOR)
    if first is None:
        raise RuntimeError("Could not read first extracted frame")
    frame_h, frame_w = first.shape[:2]

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")

    print("Lade SAM3.1 Checkpoint...")
    ckpt_path = download_ckpt_from_hf(version="sam3.1")

    print("Baue Multiplex Predictor (Notebook-Flow)...")
    predictor = build_sam3_multiplex_video_predictor(
        checkpoint_path=ckpt_path,
        use_fa3=False,
        use_rope_real=False,
    )

    session_id = None
    selected_prompt = None
    selected_nonempty_frames = 0
    selected_attempt_dir = None

    autocast_ctx = torch.autocast(device_type="cuda", dtype=torch.bfloat16) if device == "cuda" else nullcontext()
    with autocast_ctx:
        try:
            print(f"Start Session fuer Ordner: {args.frames_dir}...")
            try:
                response = predictor.handle_request(
                    request={
                        "type": "start_session",
                        "resource_path": args.frames_dir,
                        "offload_video_to_cpu": True,
                    }
                )
            except TypeError as e:
                if "offload_state_to_cpu" not in str(e):
                    raise
                print("Kompatibilitaets-Fallback fuer offload_state_to_cpu aktiv.")
                patch_offload_state_bug_if_needed(predictor)
                response = predictor.handle_request(
                    request={
                        "type": "start_session",
                        "resource_path": args.frames_dir,
                        "offload_video_to_cpu": True,
                    }
                )

            session_id = response["session_id"]

            propagation_mode = "full"
            attempt_root = os.path.join(args.masks_dir, "_attempts")
            os.makedirs(attempt_root, exist_ok=True)

            prompt_candidates = [args.prompt, "planter", "plant", "desk"]
            prompts_to_try = []
            seen = set()
            for p in prompt_candidates:
                key = p.strip().lower()
                if key and key not in seen:
                    seen.add(key)
                    prompts_to_try.append(p.strip())

            print(
                "Prompt-Fallback aktiv: " + ", ".join(prompts_to_try) +
                f" | mode={propagation_mode} | threshold={args.threshold}"
            )
            fatal_cuda_state = False

            def consume_stream(stream_obj, attempt_dir: str, processed_frames: set):
                nonlocal selected_nonempty_frames
                local_nonempty = 0
                try:
                    for response_stream in stream_obj:
                        fidx = response_stream["frame_index"]
                        local_nonempty += write_mask_from_outputs(
                            frame_idx=fidx,
                            outputs=response_stream.get("outputs", {}),
                            masks_dir=attempt_dir,
                            height=frame_h,
                            width=frame_w,
                        )
                        processed_frames.add(fidx)
                finally:
                    if hasattr(stream_obj, "close"):
                        stream_obj.close()
                selected_nonempty_frames = local_nonempty

            for prompt_text in prompts_to_try:
                if fatal_cuda_state:
                    print("Ueberspringe weitere Prompt-Versuche wegen fatalem CUDA-Zustand in diesem Run.")
                    break

                attempt_dir = os.path.join(attempt_root, sanitize_prompt_for_dir(prompt_text))
                os.makedirs(attempt_dir, exist_ok=True)
                clear_png_masks(attempt_dir)
                processed_frames = set()
                selected_nonempty_frames = 0

                print(f"\n=== Prompt-Versuch: '{prompt_text}' ===")
                _ = predictor.handle_request(
                    request={
                        "type": "reset_session",
                        "session_id": session_id,
                    }
                )

                _ = predictor.handle_request(
                    request={
                        "type": "add_prompt",
                        "session_id": session_id,
                        "frame_index": 0,
                        "text": prompt_text,
                        "output_prob_thresh": args.threshold,
                    }
                )

                print("Propagiere Maske (mode=full)...")
                try:
                    consume_stream(
                        predictor.handle_stream_request(
                            request={
                                "type": "propagate_in_video",
                                "session_id": session_id,
                                "propagation_direction": "forward",
                                "output_prob_thresh": args.threshold,
                            }
                        ),
                        attempt_dir,
                        processed_frames,
                    )
                except RuntimeError as prompt_err:
                    msg = str(prompt_err)
                    if "out of memory" in msg.lower():
                        print("Warnung: CUDA OOM im Full-Mode fuer diesen Prompt.")
                        if torch.cuda.is_available():
                            torch.cuda.empty_cache()
                        fatal_cuda_state = True
                    elif "INTERNAL ASSERT FAILED" in msg and "CUDACachingAllocator" in msg:
                        print("Warnung: CUDA Allocator ist nach Fehler inkonsistent (INTERNAL ASSERT).")
                        if torch.cuda.is_available():
                            torch.cuda.empty_cache()
                        fatal_cuda_state = True
                    elif "Tensor sizes:" in msg and "0, 256" in msg and "expanded size" in msg:
                        print("Warnung: Keine trackbaren Objekte fuer diesen Prompt erkannt.")
                    elif "No prompts are received" in msg:
                        print("Warnung: Modell hat den Prompt nicht uebernommen.")
                    else:
                        raise

                for i in range(num_frames):
                    if i not in processed_frames:
                        Image.fromarray(np.zeros((frame_h, frame_w), dtype=np.uint8)).save(
                            os.path.join(attempt_dir, f"frame_{i:05d}_obj_001.png")
                        )

                print(f"Prompt '{prompt_text}' nicht-leere Masken: {selected_nonempty_frames}")
                selected_prompt = prompt_text
                selected_attempt_dir = attempt_dir

                if selected_nonempty_frames > 0:
                    print(f"Treffer gefunden mit Prompt '{prompt_text}'.")
                    break

            if selected_nonempty_frames == 0:
                point_attempt_name = "point_fallback_center_quarter_from_bottom"
                attempt_dir = os.path.join(attempt_root, point_attempt_name)
                os.makedirs(attempt_dir, exist_ok=True)
                clear_png_masks(attempt_dir)
                processed_frames = set()
                selected_nonempty_frames = 0

                point_x = int(round(frame_w * 0.5))
                point_y = int(round(frame_h * 0.75))
                point_rel = torch.tensor([[point_x / float(frame_w), point_y / float(frame_h)]], dtype=torch.float32)
                point_abs = torch.tensor([[float(point_x), float(point_y)]], dtype=torch.float32)
                point_labels = torch.tensor([1], dtype=torch.int32)

                print("\n=== Point-Fallback: Mitte, ein Viertel von unten ===")
                print(f"Nutze Punkt (abs): x={point_x}, y={point_y}")

                _ = predictor.handle_request(
                    request={
                        "type": "reset_session",
                        "session_id": session_id,
                    }
                )

                point_response = predictor.handle_request(
                    request={
                        "type": "add_prompt",
                        "session_id": session_id,
                        "frame_index": 0,
                        "points": point_rel,
                        "point_labels": point_labels,
                        "obj_id": 1,
                        "output_prob_thresh": args.threshold,
                    }
                )

                if not isinstance(point_response, dict) or "outputs" not in point_response:
                    print("Point-Fallback mit relativen Koordinaten nicht bestaetigt, versuche absolute Koordinaten.")
                    point_response = predictor.handle_request(
                        request={
                            "type": "add_prompt",
                            "session_id": session_id,
                            "frame_index": 0,
                            "points": point_abs,
                            "point_labels": point_labels,
                            "obj_id": 1,
                            "output_prob_thresh": args.threshold,
                        }
                    )

                print("Propagiere Maske fuer Point-Fallback (vollstaendig, kein Chunking)...")
                try:
                    consume_stream(
                        predictor.handle_stream_request(
                            request={
                                "type": "propagate_in_video",
                                "session_id": session_id,
                                "propagation_direction": "forward",
                                "output_prob_thresh": args.threshold,
                            }
                        ),
                        attempt_dir,
                        processed_frames,
                    )
                except RuntimeError as point_err:
                    msg = str(point_err)
                    if "out of memory" in msg.lower():
                        print("Warnung: CUDA OOM im Point-Fallback.")
                        if torch.cuda.is_available():
                            torch.cuda.empty_cache()
                    elif "No prompts are received" in msg:
                        print("Warnung: Point-Fallback wurde vom Modell nicht als gueltiger Prompt uebernommen.")
                    elif "Tensor sizes:" in msg and "0, 256" in msg and "expanded size" in msg:
                        print("Warnung: Auch Point-Fallback lieferte kein trackbares Objekt.")
                    else:
                        raise

                for i in range(num_frames):
                    if i not in processed_frames:
                        Image.fromarray(np.zeros((frame_h, frame_w), dtype=np.uint8)).save(
                            os.path.join(attempt_dir, f"frame_{i:05d}_obj_001.png")
                        )

                print(f"Point-Fallback nicht-leere Masken: {selected_nonempty_frames}")
                selected_prompt = point_attempt_name
                selected_attempt_dir = attempt_dir

        finally:
            if session_id is not None:
                _ = predictor.handle_request(
                    request={
                        "type": "close_session",
                        "session_id": session_id,
                    }
                )
                print(f"Session {session_id} geschlossen.")

    clear_png_masks(args.masks_dir)
    if selected_attempt_dir is not None:
        for name in sorted(os.listdir(selected_attempt_dir)):
            if name.endswith(".png") and name.startswith("frame_"):
                shutil.copy2(os.path.join(selected_attempt_dir, name), os.path.join(args.masks_dir, name))

    print(f"Masken in {args.masks_dir} geschrieben.")
    print(f"Ausgewaehlter Prompt: {selected_prompt}")
    print(f"Frames gesamt: {num_frames}, nicht-leere Masken: {selected_nonempty_frames}")

    if selected_nonempty_frames == 0:
        print("Warnung: Prompt wurde verarbeitet, aber es wurden keine nicht-leeren Masken gefunden.")

    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)
