# 012. Local, deterministic balanced-plate analysis

## Context

CalSnap answers "how much did I eat?" (calories and macros) but not "what is missing from this meal?". `BALANCED_PLATE.md` asks for short, practical guidance (add vegetables, add protein, the meal is carbohydrate-heavy) that recalculates instantly while the user edits a meal, needs no additional AI request, and never reads as medical advice. The full design is in `openspec/changes/add-balanced-plate/design.md`.

## Decision

**Classification lives in the catalog only.** Each food of `protocol/nutrition/catalog.json` may carry an optional `plate: {group, quality?}` object; a food without it is `unknown`. `formatVersion` stays 1 (additive, optional field); `catalogVersion` moved 2 → 3. The server (`server/internal/nutrition`) validates the group/quality vocabulary and that `quality: mixed` only pairs with `group: other`; it never computes or returns plate analysis, and the analyze API and AI schema are unchanged. Classification was done in three user-reviewed phases (primitive foods, simple dishes, mixed dishes), reaching 100% coverage, enforced by a `TestPlateClassificationCoverage` gate (≥ 90%) and a `TestPlateStaples` pin.

**Resolution on the client through the existing catalog id.** The AI recognition path already resolves `normalizedName` (the catalog id) to a local `foods` row to fill unit data; the same lookup now also carries the food's `plate_group`/`plate_quality` into `DraftItem`. An unmatched (`ai_estimate`) item, a custom product, or a packaged product is `unknown`. This needed no protocol or OpenAPI change.

**Client schema 2 (the project's first real Drift migration).** `foods` gained nullable `plate_group`/`plate_quality` columns via an explicit `if (from == 1 && to == 2) { addColumn(...) }` step; any other `from`/`to` still throws, and the newer-schema guard is unchanged. The migration is additive only (no backfill, no destructive step), verified by a generated v1 → v2 test that asserts every existing meal, item, food, setting and correction is intact and the new columns start null. The regular startup `seedCatalog` fills them right afterward, since the seeded `catalogVersion` (3) differs from the stored one (2).

**A pure analyzer, independent of the meal feature.** `BalancedPlateAnalyzer.analyze` takes `PlatePortion` tuples (group, quality, weight), not `MealItem`/`DraftItem`, so the domain has no dependency on how the caller gets its data. `plateAnalysisProvider` (Riverpod) maps the current draft to portions and recomputes synchronously on every draft change, with no repository or network access; the same analysis reproduces for a saved meal reopened offline. The analyzer is a concrete class, not a single-implementation interface, per AGENTS.md.

**Deliberate deviations from `BALANCED_PLATE.md`**, each marked `// NOTE:` in `balanced_plate_analyzer.dart`:
- Recommendation priorities are addVegetables (100) > reduceCarbohydrateDominance (90) > addProtein (80) > addComplexCarbohydrates (10). §11.1 ranks protein above carbohydrate dominance, but that contradicts its own acceptance example (§26.1 and Example B: 50/50/300 and pasta-heavy both expect addVegetables + reduceCarbohydrateDominance, not addProtein).
- Coverage is `(total − unknown − other/mixed) / total`, not `knownEligible / total`. Under the literal §9.4 formula an ordinary drink or sauce (`other`, not `mixed`) would lower confidence for an otherwise ordinary plate.
- A fourth verdict, "reasonably balanced" (`nearlyBalanced`), covers an analyzable meal that triggers no corrective rule but falls outside the strict "nicely balanced" ranges; without it such a meal would show "could be more balanced" with no recommendation to justify it.
- No `otherRatio`/"Other" row, no `params` map, no `increaseWholeGrainShare`: the three shown ratios already sum to 100% by construction, and neither has an MVP consumer.

**Out of scope for this change** (candidates for a later iteration): `plateQuality`-driven rules (whole-grain hints), mixed-dish `composition` weights, a plate-group picker in the custom-food form, Open Food Facts category mapping, a settings toggle, and daily/trend aggregation.

## Consequences

- No protocol, OpenAPI, AI-schema, or server-config change; the only server change is validating an optional catalog field.
- The balanced-plate card adds no telemetry, logging, or network traffic; the backend never sees plate ratios or recommendations.
- Classification quality depends on a manual (if systematic and reviewed) pass over 1,253 foods; misclassification risk is mitigated by phased review, a staples pin test, and defaulting uncertain dishes to `other`/`mixed` (which yields "insufficient data" rather than wrong advice).
- Dairy-centric meals (for example a plain cottage-cheese breakfast) are excluded from the eligible weight by design and will show "insufficient data"; this is accepted for the MVP and is a candidate for v2 tuning.
- The Drift migration pattern established here (an explicit numbered step, a schema snapshot, and a generated upgrade test) is the template for future schema changes.
- Card goldens (`result_full_*`, `result_partial_*`, `balanced_plate_card_*`) were regenerated deliberately; any future change to the card's layout or copy will need the same review.
