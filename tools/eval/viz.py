"""Contact sheets of zone overlays (shared by run_face_eval.py and check_zones.py)."""
import os

import cv2
import numpy as np

TILE_W, TILE_H = 360, 380


def make_tile(vis: np.ndarray, points: np.ndarray, name: str) -> np.ndarray:
    """Crop the overlay around the face, scale it to a tile and caption it."""
    x0, y0 = np.maximum(points[:, :2].min(0).astype(int), 0)
    x1, y1 = points[:, :2].max(0).astype(int)
    pad = int(0.15 * (x1 - x0))
    crop = vis[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad]
    s = (TILE_W) / max(crop.shape[:2])
    crop = cv2.resize(crop, None, fx=s, fy=s)
    tile = np.full((TILE_H, TILE_W, 3), 255, np.uint8)
    tile[:crop.shape[0], :crop.shape[1]] = crop
    cv2.putText(tile, name, (4, TILE_H - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
    return tile


def save_sheets(tiles: list, out_dir: str, per_sheet: int = 12, cols: int = 4) -> None:
    for s in range(0, len(tiles), per_sheet):
        chunk = list(tiles[s:s + per_sheet])
        while len(chunk) % cols:
            chunk.append(np.full((TILE_H, TILE_W, 3), 255, np.uint8))
        sheet = np.vstack([np.hstack(chunk[i:i + cols]) for i in range(0, len(chunk), cols)])
        cv2.imwrite(os.path.join(out_dir, f'sheet_{s // per_sheet}.jpg'), sheet)
