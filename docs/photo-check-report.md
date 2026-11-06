# Local photo check (PR V)

Before a selfie can go to the AI, the phone checks it: **exactly one face, large enough, sharp, lit
normally, not turned, eyes not behind dark lenses, readable file**. The check runs on the phone (BlazeFace
and FaceMesh V2 from the `mediapipe_face_mesh` package the app already has). It sends nothing anywhere,
does not depend on the try-on screens, and a photo that could not be checked (damaged file, detector failure)
is refused: fail closed. A refused photo is never sent, its file is deleted and the Beauty profile is not changed.

Consent for remote analysis, the age gate and the server switch (`PHOTO_ANALYSIS`) are unchanged: this check is
an extra step before them, not a replacement.

## Rules (same numbers in `tools/eval/photo_quality.py` and `lib/services/photo_check/photo_rules.dart`)

| Check | Warn | Refuse |
|---|---|---|
| no face / damaged file / detector failure | | refuse |
| another face at least 1/4 as wide as the main one | any smaller face | refuse |
| face width, px | < 160 | < 100 |
| sharpness (variance of the Laplacian at face width 300) | < 60 | < 25 |
| brightest part of the face (p95 luma, relative to the face, not an absolute skin brightness) | < 110 | < 80 |
| blown highlights / crushed shadows on skin zones | 4 % / 25 % | 12 % / 50 % |
| grayscale (skin colour chroma) | < 3 | < 2 |
| head turn (yaw along the eye line, roll compensated) | > 0.15 | > 0.25 |
| eyes darker than the cheeks AND flat (dark lenses) | | refuse |
| uneven left/right light, little visible skin | warn only | never refuses |

Brightness is judged **inside the face**, not against a fixed skin tone, so dark skin is not refused for being dark;
a truly dark photo is refused for every skin tone (checked on synthetic faces of several tones).
EXIF orientation 1/3/6/8 gives the same face on the simulator (face width 334.4-334.7 px, yaw 0.067 in all four).

## How the thresholds were chosen and checked

* Chosen on the **development photos**: the 24 main photos, the 52 hold-out photos and synthetic defects.
* Checked once on a **fresh set** (`tools/eval/photos_eval_manifest.json`, seed 2027, 64 Wikimedia Commons photos).
  The set was judged by eye **before** the gate was run (`tools/eval/eval_judgement.json`: S suitable, M marginal,
  U unsuitable; one rater, the author, not an independent ground truth). Five photos of children were excluded
  (`photos_eval_excluded.json`), 59 remain. **No threshold was changed after seeing these results.**

### Result on the fresh set, as the app runs it (Dart, real MediaPipe, iOS Simulator iPhone 16 Pro, debug build)

| my judgement \ phone check | ok | warn (user may continue) | refused | total |
|---|---|---|---|---|
| suitable | 7 | 6 | 5 | 18 |
| marginal | 3 | 1 | 2 | 6 |
| unsuitable | 2 | 4 | 29 | 35 |

* **False refusals: 5 of 18 suitable photos.** Four are "head turned" (yaw 0.27-0.40: `e000`, `e032`, `e033`, `e050`), one is
  a man squinting in the sun taken for dark lenses (`e017`). By eye I called these frontal; the rule says they are turned.
  The yaw limit is probably too strict: to be re-examined on **another** fresh set, not on this one.
* **Wrongly accepted: 6 of 35 unsuitable photos**, all of them with a warning except two: a costume with dark glasses (`e003`, ok),
  sunglasses on a small face (`e005`, warn), a biscuit over the mouth (`e010`, warn), a crowd where the main face is small
  (`e036`, warn), a very dark frame (`e051`, ok), a small historical portrait (`e055`, warn).
* Python stand on the same photos: 4 of 18 refused, 5 of 35 let through. The phone and the stand agree on 57 of 59 verdicts
  (`tools/eval/compare_dart_python.py`).

### Parity bug found by the simulator run (fixed, not a threshold change)

The first simulator run disagreed with the stand on 11 of 59 verdicts and called 12 of 18 good photos blurry. Two causes in the
port: tall photos were decoded at most 1024 px on the long side (the stand measures the original), and the face crop was enlarged
bilinearly while the stand uses bicubic (the sharpness number depends on that). Fixed: bicubic enlargement and 2048 px decode.
After the fix 57 of 59 verdicts agree. The first run is kept in `tools/eval/out/dart/` only on this machine (out/ is git-ignored).

### Against the old filter

The old filter was the model's own confidence number (`minConfidence = 0.6`), applied **after** the photo was sent. On the 52 hold-out
photos with Gemini answers from the earlier run it let through all 36 unsuitable photos (the model says 0.6-0.9 on bad photos) and refused
none. The new check, run on the same 52 photos (Python), refused 35 of the 36 and 0 of 10 suitable ones. **These 52 photos were used to
choose the thresholds, so this is optimistic; the fresh set above is the honest number.** The old filter could not be run on the fresh set:
no new photos were sent to Gemini.

## Proof that a refused photo is not sent

Widget tests (`test/photo_check/photo_screen_check_test.dart`): for a refused photo the network spy sees 0 HTTP clients, the analyzer is
called 0 times, the file is deleted, the profile signature is unchanged and `sharePhotos` stays unset. Damaged files (empty, text,
random bytes, header only, truncated, broken middle) are all refused as unreadable with the real decoder on the simulator, nothing crashes.

## Server

The check is client side; a modified client can skip it. What the server still enforces without trusting the client: with photos off
(`PHOTO_ANALYSIS=off`, or `GEMINI_BILLING` not `paid`) every request that carries an image is `503 photo_analysis_disabled` before anything
goes to Gemini: an image in an earlier message, PNG/WebP, several images, unknown fields (`image`, `images`, `attachments`) and an image smuggled into the text
(`server/test/app.test.js`). The server cannot verify the user's age or that a local check happened. `GEMINI_BILLING=paid` must be set only after
billing is confirmed in Google AI Studio; `PHOTO_ANALYSIS=on` must not be used to get around the free tier.

## Known limits

* Masks, scarves, a hand over the face and reflective glasses are not reliably detected by colour rules; closed or squinting eyes can look like dark lenses.
* Thresholds are heuristics from a few dozen photos and one rater; a very dark frame may still pass with a face that is only moderately dark.
* Timing (debug build, simulator): median 116 ms per photo, max 1.4 s (the first photo, with detector start-up). Not measured on a physical iPhone.
* The check says "the photo is usable for colour matching", not "this is a good photo of a person" and is not a medical assessment.
