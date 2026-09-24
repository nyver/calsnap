# 007. Personal portion calibration from local corrections

## Context

The app records every time the user changes an AI weight estimate (`ai_corrections`: raw AI weight, user weight, food key). People differ systematically: someone who always serves a large side dish sees the same underestimate again and again. The goal is to use those corrections to propose better weights, without sending any diary data to the server and without a schema migration.

## Decision

**Learning happens on the device, from the existing `ai_corrections` rows.** No new table and no stored coefficients: the factors are recomputed when a recognition result arrives, from at most the 1,000 newest corrections (a bounded read). Because the correction rows are already kept in step with the diary (one row per corrected item; removed when the item or meal is deleted; restored by undo), the factors can never disagree with the data they came from, and there is no persisted format to version or migrate.

**The factor** is the exponentially weighted moving average (weight 0.3 for the newest sample) of `user weight / AI weight`, computed on the logarithm so that halving and doubling cancel out. A single ratio is limited to 0.25 .. 4 (a typo such as 1800 g for 180 g cannot dominate), the result to **0.6 .. 1.6**, and a factor within 5% of 1 is ignored.

**Three levels, most specific first; the first level with at least 3 corrections wins:**

1. the specific food (`normalizedName`);
2. its category: `light` (< 60 kcal/100 g), `carb`, `protein`, `fat` or `mixed`, derived from the per-100 g macro energy shares. The catalog has no category field and AI-estimated or custom foods never have one, so the class is computed from nutrition; side dishes such as rice, buckwheat, pasta and potatoes fall into `carb`;
3. all foods (the user's general portion bias).

A level with enough corrections is authoritative even when its factor is about 1, so a user who agrees with the AI about buckwheat is not pushed toward a category-wide bias.

**The raw AI estimate is never overwritten.** `estimatedWeightG` keeps the AI value; the draft starts from `round(estimate x factor)` and remembers it as `suggestedWeightG`. A correction is a weight that differs from what the app *proposed*, and it is recorded against the raw estimate. Accepting a proposal records nothing. This prevents a feedback loop in which the app learns from its own output; it also means confirmations do not strengthen a factor, only disagreements move it. To tell an accepted proposal from a correction after the meal is saved (edit and undo flows), `MealItem.weightCorrected` is "a correction row exists for the item".

**Transparency and control.** An adjusted item is labeled "adjusted" with the note "AI estimated N g. Adjusted to your usual portions." A setting ("Adapt weights to my corrections", key `personalize_portions`, on by default) turns it off; "Clear all data" removes the corrections. If reading the corrections fails, the draft falls back to the AI estimates.

## Consequences

* No data leaves the device; the request to the backend is unchanged.
* No database migration; the existing rows work from day one, including corrections recorded by earlier versions (which are all against the raw estimate).
* Recomputing costs one indexed read of at most 1,000 rows plus one lookup of the corrected foods per analysis.
* The category is a heuristic. Mixed dishes land in `mixed` and rarely share a useful factor; the food level covers them once enough corrections exist.
* Only weights are personalized, not nutrition values.
