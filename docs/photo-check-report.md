# Local photo check (PR V / #36)

Before a selfie can go to the AI, the phone checks it: **exactly one face, large enough, sharp, lit normally,
not strongly turned, readable file**. The check runs on the phone (BlazeFace and FaceMesh V2 from the
`mediapipe_face_mesh` package the app already has). It sends nothing anywhere, does not depend on the try-on
screens, and a photo that could not be checked (damaged file, detector failure) is refused: fail closed.
A refused photo is never sent, its file is deleted and the Beauty profile is not changed.

Consent for remote analysis, the age gate (18+) and the server switch (`PHOTO_ANALYSIS`) are unchanged: this
check is an extra step before them, not a replacement.

## What happens to each verdict (three outcomes)

| Outcome | What the user sees | Can the photo go to Gemini? |
|---|---|---|
| **Accepted** (`ok`) | nothing, goes on | yes, after the server switch and the user's consent |
| **Retake suggested** (`warn`) | "The photo can be used, but the result may be less accurate", the reasons, buttons "Use this photo" and "Choose another photo" | yes, **only if the user taps "Use this photo"**, then the same server switch and consent apply |
| **Refused** (`reject`) | "This photo does not fit", the reason, "Choose another photo" or "Continue without a photo". **No "use anyway" button** | **never**: the file is deleted, nothing is sent |

Refused (cannot be confirmed by the user): damaged or unreadable file, no face, the face detector failed,
**another face at least a tenth as wide as the main one** (a recognisable bystander), face under 100 px,
sharpness under 25, the brightest part of the face under 80 (really dark), black and white, strongly turned head
(> 0.30), strong blown highlights or crushed shadows.

Retake suggested (user may continue): smaller or distant face, slightly soft, somewhat dark, slightly blown, grayscale-ish,
turned head (0.15-0.30), a tiny face far in the background, **dark lenses or a squint** (they cannot be told apart),
little visible skin (hair, beard, shadow), strong side light.

Brightness is judged **inside the face**, not against a fixed skin tone, so dark skin is not refused for being dark;
a really dark photo is refused for every skin tone (synthetic faces of several tones are in the tests).

## Why these rules changed after the first evaluation (round 1 -> round 2)

Round 1 (59 fresh photos, judged by eye before the gate was run) gave 5 false refusals of 18 suitable photos and 6 unsuitable
photos let through. Each of the 11 cases:

| Photo | What it is | Gate said | Cause | Decision |
|---|---|---|---|---|
| e000 | head turned about 30 deg | refused (yaw 0.26) | my label "frontal" was too generous; limit 0.25 sat at the low end of the gap on the development photos (suitable <= 0.196, turned >= 0.333) | limit moved to 0.30 (inside that gap) |
| e032, e033, e050 | turned 0.32-0.38 | refused | same range as development photos I had called "turned" (0.333-0.40): the label was inconsistent, the rule was not | stay refused by the 0.30 limit |
| e017 | squint in hard sun | refused as dark lenses | a squint and sunglasses give the same flat dark eyes | dark/flat eyes became a **warning**, never a refusal |
| e003 | costume + dark glasses with frame texture | ok | lens region has texture | known limit |
| e005 | sunglasses, small face | warn | correct as a warning now | - |
| e010 | biscuit over mouth and nose | warn (side light) | the biscuit has skin-like colour; the lips-vs-skin colour distance of a covered mouth (1-8) overlaps with normal pale lips on the development photos | **not detectable by colour; known limit** |
| e036 | woman signing, others behind | warn (small face 129 px) | the people behind were not detected as faces | known limit |
| e051 | man in a dark hall | ok | brightest part of the face 120, same as two legitimate development photos (116, 120) | known limit; a stricter limit would refuse those |
| e055 | old sepia print | warn | a photo of a photo is not detectable | known limit |

Policy changes (made on the development photos and on the harm of each outcome, not on round-1 numbers):
yaw reject 0.25 -> 0.30; any other face >= 10 % of the main face width refuses (was 25 %, and any smaller one only warned);
dark/flat eyes warn instead of refuse. Nothing was tuned on the final set below.

## Final evaluation on an independent set (round 2)

* Never used to choose a threshold or a rule: `tools/eval/photos_final_manifest.json` (seed 2028, 97 Wikimedia Commons photos, skips every photo
  of the earlier sets), including portraits of many countries, hands on the face, paintings, wax figures, statues, a face reflected in a helmet.
* Judged by eye **before** the gate was run (`tools/eval/final_judgement.json`: S suitable, W retake suggested, U must be refused). Eight photos
  of children or partial nudity were excluded (`photos_final_excluded.json`), 89 remain. One rater, not an independent ground truth.
* Result of the phone check as the app runs it (Dart, real MediaPipe, iOS Simulator iPhone 16 Pro, debug build):

| my judgement \ phone check | accepted | retake suggested | refused | total |
|---|---|---|---|---|
| suitable (S) | 5 | 14 | 1 | 20 |
| retake suggested (W) | 3 | 5 | 5 | 13 |
| must be refused (U) | 0 | 5 | 51 | 56 |

* **Suitable photos refused: 1 of 20** (`f007`, sharpness 23.1 against a limit of 25, a soft but usable selfie).
* **Photos that must be refused but got only a retake suggestion: 5 of 56** (`f022` nearly black-and-white, `f026` sunglasses on a 106 px face,
  `f042` and `f079` faces of about 100-130 px in a full-length frame, `f087` face in the shadow of a cap). **None passed without any message.**
  Recognisable second faces, no face, a picture/sculpture of a face and hands covering the mouth were refused (41 "no face", 3 "several faces").
* **Suitable photos that got a retake suggestion: 14 of 20, 9 of them "head turned"** (yaw 0.15-0.30). The 0.15 warning limit is too sensitive:
  on the development photos suitable photos reach 0.196. It is only a suggestion (the user can continue), but it is shown too often.
  **Recommendation: raise the warning limit to about 0.20 and check it on another fresh set.** It was not changed here, because this set is now used.
* The phone and the Python stand agree on 88 of 89 verdicts (`tools/eval/compare_dart_python.py`).
* Different skin tones: dark-skinned people in the set (`f014`, `f020`, `f088`) were not refused (accepted, accepted with side light, accepted with a
  turn warning); synthetic faces of several tones are accepted at normal light and refused when dark. There are only a few real dark-skinned suitable photos, so this
  is a weak statistical statement.
* Speed (debug build, simulator): median 116 ms, max 1.0 s per photo. Not measured on a physical iPhone.

### Against the old filter

The old filter was the model's own confidence number (`minConfidence = 0.6`) applied **after** the photo was sent. On the 52 hold-out photos with Gemini answers from the earlier run
it let through all 36 unsuitable photos and refused none. The new check on the same photos (development set, so optimistic): 35 of the 36 refused, 0 of 10 suitable refused. The old
filter could not be run on the final set: no new photos were sent to Gemini.

## Parity bug found by the simulator run (fixed earlier, not a threshold change)

The first simulator run disagreed with the stand on 11 of 59 verdicts. Two causes in the port: decoding at most 1024 px on the long side (the stand measures the original) and
bilinear enlargement where the stand uses bicubic (the sharpness number depends on that). Fixed: bicubic enlargement and 2048 px decode.

## Proof that a refused photo goes nowhere, and what else stands in front of the AI

Widget tests (`test/photo_check/photo_screen_check_test.dart`): for a refused photo the network spy sees 0 HTTP clients, the analyzer is called 0 times, the file is deleted,
the profile signature is unchanged and `sharePhotos` stays unset; a refusal screen has no "use this photo" button. A **good** photo still goes nowhere when: the user is 17 or the age
is unknown, the server switch is off (free tier), the server is unreachable (only the body-less `/health` ping is allowed), or the user has not agreed (the dialog comes first, "Cancel"
sends nothing). Damaged files (empty, text, random bytes, header only, truncated, broken middle) are refused as unreadable with the real decoder on the simulator.

On the simulator (`integration_test/photo_screen_sim_test.dart`, real screen, real MediaPipe, counting analyzer): a refused photo (several faces, no face, hands over the mouth) showed
"This photo does not fit... not sent and deleted from the phone", analyzer calls 0, file deleted, profile unchanged; a turned head showed the warning screen with both buttons; a good photo
went to the consent dialog with analyzer calls 0 until the user agrees.

## Server

The check is client side; **a modified client can skip it. The local check is not a defence against a modified client.** What the server still enforces without trusting the client: with
photos off (`PHOTO_ANALYSIS=off`, or `GEMINI_BILLING` not `paid`) every request that carries an image is `503 photo_analysis_disabled` before anything goes to Gemini: an image in an
earlier message, PNG/WebP, several images, unknown fields (`image`, `images`, `attachments`) and an image smuggled into the text (`server/test/app.test.js`). The server cannot verify the
user's age or that a local check happened. `GEMINI_BILLING=paid` must be set only after billing is confirmed in Google AI Studio; `PHOTO_ANALYSIS=on` must not be used to get around the free tier.

## Known limits

* Masks, scarves, a hand or an object (a biscuit) over the face, a photo or drawing of a face, and reflective glasses are not reliably detected by colour rules;
  a covered mouth is only caught when the face becomes small, turned or has several faces.
* People behind the main person are caught only when the detector finds their faces (small ones are not found).
* Thresholds are heuristics from a few dozen photos and one rater; a moderately dark photo (brightest part of the face about 120) passes.
* The face check says "the photo is usable for colour matching", it is not an age check and not a medical assessment. Age (18+) is taken from the profile and cannot be checked on the server.
* Not measured on a physical iPhone; the simulator checks used screenshots and an automated test, not a person tapping.
