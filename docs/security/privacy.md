# Privacy note

This document is the source for the in-app privacy screen and the public privacy policy. The in-app text is bundled with the app (localization resources) and works offline.

## What is stored, and where

| Data | Where | Retention |
|---|---|---|
| Meals, items, nutrition values, settings, AI correction records, custom products | SQLite database in the app-private directory of the device | Until the user deletes it (Settings, "Clear all data") or uninstalls the app |
| Meal photos | Files under `meals/YYYY/MM/DD/` in the app-private documents directory; only the relative path is stored in SQLite | Until the meal is deleted, or never stored when "Save meal photos" is off |
| Temporary photos (capture, exports) | App cache / temp directories | Deleted after analysis or discard, and swept at every app start |

The app declares `allowBackup="false"`: the diary is not copied to Google cloud backup. The only supported way to take data off the device is the user-initiated CSV/JSON export.

## What leaves the device

Only when the user analyzes a photo, the app sends to the CalSnap backend over HTTPS:

* the prepared photo: downscaled, orientation applied, re-encoded as JPEG so that all metadata (EXIF, including GPS) is removed;
* the app language (`ru` or `en`);
* the plate diameter, if the user set one;
* a random request id (`X-Request-Id`).

Nothing else is sent: not the diary, not the settings, not device identifiers, no account (there is none).

## What the backend does with it

* Processes the photo in memory only, forwards it to the configured AI provider (currently Google Gemini through its API) together with the language and plate diameter, and returns the result. The photo is never written to disk or any store and is dropped when the request completes.
* Keeps a short-lived in-memory cache of the *response* (not the photo) keyed by the request id, so that a retry after a lost connection does not trigger a second AI call. It is bounded and expires after 10 minutes.
* Logs request id, route, status, sizes, durations, error codes and item counts. Logs never contain photos, prompts, AI output, food names or API keys.
* Exposes technical metrics without content or client addresses.
* Stores no diary, meal history or user profile. There is no database.

## The AI provider

The photo is processed by the AI provider chosen by the operator. The provider's own terms govern how long it may retain the request and whether inputs may be used for model training. **Before publishing, the operator must review those terms for the chosen provider and plan and state them in the public policy**: use a plan or setting under which inputs are not used for training, where the provider offers one. The API key is held only by the backend (an environment variable) and is never part of the app, the config file, logs or client builds.

## Security measures

* HTTPS only in release builds (cleartext is disabled; a narrow cleartext exception exists only in debug builds for a local development backend). Server TLS minimum is 1.2 when the server terminates TLS.
* The backend validates every upload: size, real image format by content, dimensions, request id shape.
* The database rejects data written by a newer app version instead of modifying it.
* CSV export neutralizes spreadsheet formulas.

## User controls

* Turn off "Save meal photos": photos are deleted right after a successful analysis and meals are saved without one.
* Delete a single meal (with a short undo window) or clear all data.
* Export the diary (CSV or JSON).
