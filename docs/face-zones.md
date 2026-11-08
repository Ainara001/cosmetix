# Face zones and the person's skin marks

Stages 5 and 6 (first version) of the spec.

## Zones (`lib/core/face/face_zones.dart`)

Five zones from the 478-point MediaPipe mesh: forehead, right cheek, left
cheek, nose, chin (left / right are the person's). The loops are exactly the
ones of the photo check and of the reference `tools/eval/face_zones.py`
(checked by eye on the evaluation photos); the photo check now reads them
from this file, so there is one zone system for measurements, photo
comparison and the try-on.

- The face contour is not used (it hits ears and hair); the forehead stops at
  the top of the mesh.
- Eyes, **brows** and lips are cut out with a margin of 1.2% of the face width.
  (The reference forehead loop runs along the lower edge of the brows; the
  photo check keeps its reference behaviour, these zones exclude the brows.)
- A cheek smaller than 45% of the other one is turned away: `visible = false`.
- Not detected from the mesh: hair over the forehead, glasses, a hand, make-up.
  The person confirms what they see.

Pure geometry in any coordinate system (photo, preview, schematic face).
Tests: `test/core/face/face_zones_test.dart` (areas, no overlap on a dense
grid, eyes / brows / lips never skin, rotation and scale, turned cheek).

## Skin marks (`SkinMarksScreen`, "Мой уход" → «Отметить особенности кожи»)

The person picks a zone (on a schematic face, or over their own photo, which
stays in memory only) and marks what they see: breakouts, blackheads,
redness, marks left by breakouts, dark spots, scars, visible pores, uneven
texture. **These are observations, not a diagnosis; nothing is detected
automatically.** Automatic classification of skin conditions is a later
stage and needs a model whose accuracy is measured independently, on all
skin tones (see `docs/skin-analysis-research.md`).

Stored on the phone only: SQLite v19, table `skin_zone_marks` (one row per
zone + feature, codes checked by the database, deleted with the account and
by "delete all data").

Marks map to profile concerns only where the meaning is the same:
breakouts / blackheads → acne; marks after breakouts → acne + pigmentation;
dark spots → pigmentation; redness → sensitivity. Scars, pores and texture
are kept but not mapped; scars show a note to see a dermatologist.
The care selection reads these concerns (separate PR on top of the care
selection branch).
