# 001. Shared nutrition catalog

## Context

Both sides need the same nutrition data. The backend matches recognized food names to a profile and must not rely on the AI alone for calories. The client must search foods and convert units offline from the first run. `go:embed` cannot reference files outside its module and Flutter assets must live inside the app package, so one physical file cannot serve both.

## Decision

`protocol/nutrition/catalog.json` is the canonical catalog (`formatVersion` 1, integer `catalogVersion`, cooking/serving `modifiers` per language, about 200 foods with English and Russian names, aliases, per-100 g values, optional `gramsPerPiece`, `gramsPerPortion`, `densityGPerMl`, and a `source`). Values are typical public values (USDA FoodData Central).

Each side embeds a byte-identical copy: `server/internal/nutrition/catalog.json` and `apps/client/assets/catalog/foods.json`. `scripts/sync-catalog.sh` refreshes both, and a test on each side fails when its copy differs from the canonical file.

Matching keeps modifier words in catalog names (so "fried rice" and "rice" stay distinct entries) and looks up both the modifier-preserving and the modifier-free key of an AI name: exact id, alias, then fuzzy matching, then the AI's own estimate.

On the client the catalog seeds the `foods` table. A newer `catalogVersion` updates `source = 'catalog'` rows in place (ids stay stable) and removes catalog rows that disappeared, but never touches user products or cached AI estimates.

## Consequences

* One review point for nutrition data; a contract test catches drift.
* Two copies must be committed; forgetting to sync fails the tests rather than shipping silently.
* Catalog quality bounds the quality of totals for matched foods; unmatched foods carry the AI estimate and a warning.
* Replacing the catalog by an external food API only requires another `NutritionProvider`.
