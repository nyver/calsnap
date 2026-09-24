# 011. Reading a nutrition label with the vision provider

## Context

A barcode the database does not know ([ADR 010](010-barcode-lookup-via-backend.md)) leaves the user typing four numbers from the package. The package itself has them. Two ways to read them: on-device text recognition, or the AI vision provider that already reads meal photos.

## Decision

**The vision provider reads it, through the backend.** On-device OCR would keep the photo on the phone, but Google ML Kit's text recognition has no Cyrillic model, and a large share of the target labels are Russian ("Белки", "Жиры", "Углеводы", "ккал"). A general vision model reads both languages, tolerates curved and glossy packaging and understands the layout (per 100 g next to per serving). It reuses the existing provider integration, keys, retries and rate limit. The price is that the label photo goes to the AI provider, exactly like a meal photo (prepared JPEG without metadata, not stored by CalSnap); the privacy note and the in-app text say so.

**Contract (additive, API stays `v1`).** `POST /v1/labels/analyze` takes one `image` and `locale` and returns values per 100 g, an optional serving size and product name, and warnings. `GET /v1/config` advertises `labelReading`; without it the app hides the feature. A photo without a readable table is `422 LABEL_NOT_RECOGNIZED`. The AI output contract is `protocol/ai/nutrition-label-result.schema.json`: a *transcription*, values exactly as printed, absent when not visible; the prompt forbids estimating or calculating anything that is not on the package.

**Normalization is the server's job, deterministic and tested.** The model reports what the table is for (`per_100g`, `per_100ml`, `per_serving`) and the serving size; the server converts a per-serving table with the printed serving size, converts kJ to kcal when kcal is missing and reports the outcome as warnings: `VALUES_CONVERTED`, `VOLUME_BASIS` (per 100 ml is used as per 100 g), `ENERGY_ESTIMATED` (no printed energy: computed from complete macros), `ENERGY_MISMATCH` (energy far from what the macros imply; fibre and polyols explain small gaps) and `LOW_CONFIDENCE`. A per-serving table without a serving size is not usable. Values are validated twice, as printed and after the conversion (physical limits per 100 g); impossible values mean a misread and are retried once. **A value the table did not show is omitted, never zero**, so the app leaves it empty instead of saving a wrong 0.

**Confirmation before saving.** The result opens the custom product form filled with what was read, with notes on what was converted or looks doubtful and always "Check every value against the package before saving". Nothing is stored until the user taps Create; missing values keep the button disabled. The product is a normal custom product (`source = user`) in the local database, together with its barcode (`sourceId`, and the digits as a searchable alias) and the serving when known. The next scan of that barcode is answered locally, offline, without a backend call, and the user's own product wins over a cached one.

**Entry points.** From the barcode scanner's "not found" screen (the chain: barcode, not found, scan label, read, confirm, save; the barcode is attached to the product) and from the custom product form of the meal editor ("Fill from a label photo", no barcode). The label camera is the capture screen in a third mode: no plate guide and no manual entry, but the blur and light checks of [ADR 009](009-local-photo-checks-and-plate-guide.md), which matter most for text.

## Consequences

* No schema change or migration; a new custom-product field set (barcode, serving) uses existing columns.
* The photo of a label is sent to the AI provider. Operators using a router (OpenRouter, RouterAI) should remember that it reaches the upstream vendor, as for meals.
* A model can misread digits. The confirmation step, the warnings and the range checks reduce the risk; they cannot remove it, which is why the values are shown, editable and never saved automatically.
* One extra AI call per label; it shares the analysis rate limit and the concurrency slots' budget, and has its own slot pool of the same size.
* A future on-device recognizer (for example with a Cyrillic-capable model) could replace or precede the provider without changing the client contract of the form.
