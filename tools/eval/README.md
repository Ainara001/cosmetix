# Face-analysis evaluation stand

Python scripts only; the app is not touched. Results and what they mean:
[`docs/skin-eval-report.md`](../../docs/skin-eval-report.md).

## Setup (once)

Python 3.12 (the report was produced with 3.12.12 on macOS arm64). Versions are pinned in
`tools/eval/requirements.txt`; the model file is checked against a SHA-256.

```bash
python3.12 -m venv tools/.venv      # if `python3.12` is not found, use the full path of your Python 3.12 (for example from pyenv)
tools/.venv/bin/pip install -r tools/eval/requirements.txt
tools/.venv/bin/python tools/eval/fetch_model.py        # face_landmarker.task, SHA-256 checked
tools/.venv/bin/python tools/eval/fetch_photos.py       # licensed photos -> tools/eval/data/photos (checked, git-ignored)
tools/.venv/bin/python -m unittest discover tools/eval/tests
```

`tools/.venv`, `tools/eval/data`, `tools/eval/models` and `tools/eval/out` are git-ignored.
The Face Landmarker needs no GPU; CPU only.

## Scripts

| Script | What it does |
|---|---|
| `face_zones.py` | Module: MediaPipe Face Landmarker (478 points) -> forehead, both cheeks, nose, chin as masks (eyes and lips cut out, edges eroded), head-turn estimate |
| `photo_quality.py` | Module: OpenCV quality gate (face size, sharpness, dark photo, blown highlights, side light, head turn) -> `ok` / `warn` / `reject` with reasons |
| `run_face_eval.py` | Zones + quality + timing over `data/photos`; writes overlays to look at, CSVs, `timing.txt` into `out/face` |
| `run_quality_eval.py` | Applies known degradations (blur, dark, bright, small face) to good photos and counts how many the gate flags |
| `viz.py` | Overlay tiles and contact sheets (used by `run_face_eval.py` and `check_zones.py`) |
| `check_zones.py` | Quick overlay + contact sheet for any folder of photos |
| `skin_eval.py` | Scaffold: `labels.csv` + `predictions.csv` -> confusion matrices, precision / recall / specificity / F1 with 95% Wilson intervals for acne, scar, redness; severity matrix, macro-F1, weighted kappa |
| `run_gemini_set.py` | App prompt on a whole folder next to the gate: how many photos the gate refuses that Gemini still answers with confidence >= 0.6 |
| `run_wb_sensitivity.py` | White-balance cast / darker / brighter / filter on the same photos: local skin colour shift and (with `--gemini`) answer changes |
| `build_holdout_manifest.py`, `holdout_agreement.py` | Random hold-out / stress set of licensed photos from Commons; gate verdicts against a person's judgement (`holdout_judgement.json`) |
| `scan_claims.py` | Statements about skin condition inside the model's free text (`observations` are shown to the user) |
| `dataset_facts.py` | Counts from the public metadata of SCIN and Fitzpatrick 17k (no images) |
| `compare_old_zones.py`, `summarize_results.py`, `make_report_assets.py` | Tables and charts of `docs/skin-audit-report.md` from the output files |
| `gemini_repeat.py` | Same photo N times through `server/` `POST /v1/chat` with the app's own prompt: latency, JSON validity, agreement between runs |
| `tests/` | Hand-checked tests: metric formulas, input-file errors, head pose, quality-gate thresholds, photo verification |

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
