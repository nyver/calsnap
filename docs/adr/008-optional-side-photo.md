# 008. Optional side photo for volume estimates

## Context

Portion size from one top-down photo is the weakest part of the estimate: the height of rice, pasta, potatoes, salads, cakes and meat is invisible from above. A second photo taken from the side shows it. Most users will keep using one photo, so the second one must be an offer, never a step, and the existing API, clients and servers have to keep working.

## Decision

**Contract (additive, API stays `v1`).** `POST /v1/meals/analyze` accepts an optional second file part `sideImage` next to `image`: same formats (JPEG, PNG, WebP by content), same per-image size and dimension limits, at most one. `GET /v1/config` gains `maxImages` (2 on servers that support it). A client sends `sideImage` only when the cached config says `maxImages` is 2; a missing field means 1, so a new app against an old server never shows the offer and never sends a part that server would reject. An old app against a new server simply sends one image. The request body limit is two images plus form overhead; the request still costs one rate-limit token and one analysis slot.

**Server.** `analysis.Request.SideImage` and `RequestContext.SideImage` carry it to the provider, which appends it as a second image after the main one (Gemini `inlineData` part, OpenAI-compatible `image_url` part). The user prompt (prompt version `v2`) tells the model that the first photo is from above and the second from the side, to use the side view for height and volume, and to report each food once. The replay/dedup key hashes both images, so a request id plus the same main photo can never return a result that was computed without (or with a different) side photo. Nothing is stored; both images stay in memory for the request.

**Client.** After a normal recognition the result screen shows a low-emphasis text button "Improve accuracy" with a one-line hint. It appears only for a fresh recognition of a single photo, and only when the server allows two images. It opens the capture screen in side mode (camera or gallery, no manual entry, a hint to hold the camera at plate level), which runs the usual analysis screen with the draft's main photo plus the new one. On success the items of the *same draft* are replaced (meal time, meal type and stored photo are kept, personal portion factors apply again, see [ADR 007](007-personal-portion-calibration.md)) and the offer disappears; the result is marked "Estimated from two photos". Because the new result replaces edited items, the app asks for confirmation first when the user already changed anything, and cancelling changes nothing. If the second analysis fails, the analysis screen offers "Keep the first result" instead of manual entry, and the first result is untouched.

The prepared main JPEG is kept in the in-memory draft (`MealDraft.sourceJpeg`, typically a few hundred KB, at most the upload limit) so the second request can carry it even when saving photos is off; it is never persisted. Only the main photo is stored with the meal; the side photo is a temporary file that is deleted with the analysis.

## Consequences

* No schema or persisted-format change, and no migration.
* A two-photo analysis sends and pays for two images (roughly twice the input tokens); the offer being optional keeps the average cost close to today's.
* The privacy note and the in-app privacy text say that two photos are sent when the user adds a side photo.
* The quality gain depends on the model following the prompt; the prompt is versioned so it can be tuned without another contract change.
* Not done: choosing which foods to suggest the side photo for. The offer is shown for every fresh recognition; the hint names the foods where it helps most.
