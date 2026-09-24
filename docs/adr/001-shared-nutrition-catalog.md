# 001. Shared nutrition catalog

## Context

Both sides need the same nutrition data. The backend matches recognized food names to a profile and must not rely on the AI alone for calories. The client must search foods and convert units offline from the first run. `go:embed` cannot reference files outside its module and Flutter assets must live inside the app package, so one physical file cannot serve both.

## Decision

`protocol/nutrition/catalog.json` is the canonical catalog (`formatVersion` 1, integer `catalogVersion`, cooking/serving `modifiers` per language, about 1,250 foods with English and Russian names, aliases, per-100 g values, optional `gramsPerPiece`, `gramsPerPortion`, `densityGPerMl`, and a `source`). Values are approximate typical values referenced to USDA FoodData Central and Russian composition tables; they are not imported from a database. Version 2 grew the catalog from about 200 to about 1,250 foods (basic ingredients, popular dishes, a large Russian/CIS section) without removing or renaming any id, so version 1 rows update in place.

Each side embeds a byte-identical copy: `server/internal/nutrition/catalog.json` and `apps/client/assets/catalog/foods.json`. `scripts/sync-catalog.sh` refreshes both, and a test on each side fails when its copy differs from the canonical file.

Matching keeps modifier words in catalog names (so "fried rice" and "rice" stay distinct entries) and looks up both the modifier-preserving and the modifier-free key of an AI name: exact id, alias, then fuzzy matching, then the AI's own estimate. In the fuzzy stage a catalog name that contains numbers ("kefir 2.5%") only qualifies when the AI name has the same numbers, so percentage variants are never confused, and a length check skips candidates that cannot reach the similarity threshold, which keeps an unmatched name at well under a millisecond with a catalog of this size.

On the client the catalog seeds the `foods` table. A newer `catalogVersion` updates `source = 'catalog'` rows in place (ids stay stable) and removes catalog rows that disappeared, but never touches user products or cached AI estimates.

## Consequences

* One review point for nutrition data; a contract test catches drift.
* Two copies must be committed; forgetting to sync fails the tests rather than shipping silently.
* Catalog quality bounds the quality of totals for matched foods; unmatched foods carry the AI estimate and a warning. The larger catalog raises coverage but also the review burden of its values; a consistency test (kcal against 4P+9F+4C) catches typos, not systematic errors.
* Adding a specific dish can take an alias away from a generic entry (for example "pea soup" moved from `soup` to `pea_soup`); ids are never reassigned, so stored meal items keep their references.
* The client seeds about 1,250 rows on the first launch after a catalog version change and filters them in Dart per search; both were measured in the millisecond-to-sub-second range on a desktop host, and should be re-measured on a device before the catalog grows several times larger.
* Replacing the catalog by an external food API only requires another `NutritionProvider`.
