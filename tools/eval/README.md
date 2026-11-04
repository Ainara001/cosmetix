# Face-analysis evaluation stand

Python scripts only; the app is not touched. Results and what they mean:
[`docs/skin-eval-report.md`](../../docs/skin-eval-report.md).

## Setup (once)

```bash
python3.12 -m venv tools/.venv
tools/.venv/bin/pip install mediapipe opencv-python-headless numpy
mkdir -p tools/eval/models
curl -L -o tools/eval/models/face_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
python3 tools/eval/fetch_photos.py      # 24 licensed photos -> tools/eval/data/photos (git-ignored)
```

`tools/.venv`, `tools/eval/data`, `tools/eval/models` and `tools/eval/out` are git-ignored.

## Scripts

| Script | What it does |
|---|---|
| `face_zones.py` | Module: MediaPipe Face Landmarker (478 points) -> forehead, both cheeks, nose, chin as masks (eyes and lips cut out, edges eroded), head-turn estimate |
| `photo_quality.py` | Module: OpenCV quality gate (face size, sharpness, dark photo, blown highlights, side light, head turn) -> `ok` / `warn` / `reject` with reasons |
| `run_face_eval.py` | Zones + quality + timing over `data/photos`; writes overlays to look at, CSVs, `timing.txt` into `out/face` |
| `run_quality_eval.py` | Applies known degradations (blur, dark, bright, small face) to good photos and counts how many the gate flags |
| `check_zones.py` | Quick overlay + contact sheet for any folder of photos |
| `skin_eval.py` | Scaffold: `labels.csv` + `predictions.csv` -> confusion matrices, precision / recall / specificity / F1 with 95% Wilson intervals for acne, scar, redness; severity matrix, macro-F1, weighted kappa |
| `gemini_repeat.py` | Same photo N times through `server/` `POST /v1/chat` with the app's own prompt: latency, JSON validity, agreement between runs |
| `tests/test_skin_eval.py` | Hand-checked tests of the metric code: `tools/.venv/bin/python -m unittest discover tools/eval/tests` |

## Label format for `skin_eval.py`

```
labels.csv       image,acne,scar,redness[,severity][,source][,licence]
predictions.csv  image,acne,scar,redness[,severity]
```

Cells are `0` / `1`; blank in labels = not labelled (that image is skipped for
that class), blank in predictions = no answer (counted and reported, never
dropped silently). A class with fewer than 30 positives or negatives is printed as
UNRELIABLE.

## Rules

* Photos: only your own consenting subjects or public ones with a clear licence
  (`photos_manifest.json` lists licence and author of each). Never a private photo
  of a real user, and never through `gemini_repeat.py` unless the photo may leave
  this machine.
* No number goes into the report without a run or a source.
