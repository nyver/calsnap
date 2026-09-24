# 009. Local photo checks, a plate guide and a reusable plate size

## Context

Portion size is the weakest part of a photo calorie estimate, and it depends on things the user controls: how the plate is framed, how sharp and well lit the photo is, and whether the app knows the plate's real size. The backend already accepts an optional plate diameter as a scale reference. Advice about the photo should not cost an AI call, must not send anything anywhere and must never make the usual flow harder.

## Decision

**Guide.** The viewfinder shows a dashed plate outline with "Hold the camera directly above the plate". It is drawn over the preview, ignores touches and never blocks the shutter. It is not shown for the side photo of [ADR 008](008-optional-side-photo.md).

**Checks on the captured or picked photo, on the device.** After the preview appears (the buttons work at once) the photo is decoded in an isolate, shrunk to 320 px and checked:

* *blurry*: the 90th percentile over an 8 x 8 tile grid of the Laplacian variance. Judging the sharpest tiles keeps a smooth soup or a bare tablecloth from looking blurry;
* *too dark* / *too bright*: mean luma, plus the share of blown-out pixels;
* *steep camera angle*: a circular plate photographed at tilt t appears as an ellipse whose minor/major axis ratio is about cos(t). The plate is found by RANSAC ellipse fitting on Sobel edges (per connected edge component, requiring the fitted outline to be supported by enough edge pixels facing along its normal and to cover most of its perimeter). A ratio below 0.72 (about 44 degrees) is reported;
* *plate cut off*: the fitted ellipse extends beyond the frame by 10% of its diameter or more.

The result is advice: a banner "Retake for a better estimate?" with at most two problems (geometry first) and the text, for example, "The plate is shot at a steep angle. For a more accurate portion estimate, take the photo from above." "Retake" becomes the highlighted action; "Analyze" always stays available. A photo that cannot be decoded or judged gets no banner. Side photos get only the blur and light checks.

**Silence over false alarms.** Detection returns "unknown" for anything doubtful: no plate, a square plate or board, a cluttered table. There is deliberately no "plate not found" message, because the algorithm cannot tell a missing plate from an unusual one. An oval platter can look like a tilted round plate and produce a wrong angle warning; this is accepted because the warning is dismissible.

**Thresholds are heuristics.** They were tuned on synthetic pictures (drawn plates with noise, blur and darkening, also encoded as real JPEGs), not on a labeled set of meal photos, so they are set leniently and live in one place (`PhotoThresholds`). They should be revisited with real photos.

**Plate size.** The saved `plate_diameter_cm` setting is now presented as "My usual plate". The photo preview has a chip ("My usual plate: 26 cm", or "Add plate size") that opens a sheet with one-tap sizes (20 to 30 cm), a custom field validated like the setting (10 to 40 cm), "No plate size" and a switch "Remember as my usual plate" (on by default). With the switch off the choice applies to that analysis only (`AnalysisSource.plateOverride`) and the saved plate stays untouched, which covers eating from someone else's plate. No new persisted key or migration is needed.

## Consequences

* Everything runs locally; no new API field, no network call, no persisted format change.
* Each photo is decoded once more for the checks (in a background isolate); a 12 MP photo takes a moment, and the preview does not wait for it.
* Sensor-based tilt (the accelerometer) would be exact for camera photos, but would need a new native dependency and cannot judge gallery photos; the image-based check works for both. It remains a possible refinement, as does sending the detected plate size in pixels to the backend as a scale hint.
* The angle estimate assumes a round plate and a distant camera (weak perspective); it is a coarse gate, not a measurement.
