# 010. Barcode lookup for packaged products through the backend

## Context

For a packaged product a photo of the plate is the wrong tool: the label already states the exact nutrition, and the AI can only guess it. Open Food Facts (OFF) is a large crowd-sourced database keyed by barcode, free to read and licensed under the ODbL. The app so far talks to one server only (the CalSnap backend), and its privacy note promises that nothing but the analyzed photo, the language and the plate size leaves the device.

## Decision

**Lookup goes through the backend.** `GET /v1/products/{barcode}?locale=` returns the product (name, brand, serving size when declared, nutrition per 100 g, `source: openfoodfacts`); unknown or unusable products are `404 PRODUCT_NOT_FOUND`, a failing source `503 PRODUCT_SOURCE_UNAVAILABLE`. The app never contacts OFF: the user's address stays hidden from a third party, the source can be swapped or mirrored server-side (`products.base_url`), the server sets the required `User-Agent`, and the client keeps one network peer. `GET /v1/config` advertises `barcodeLookup`; without it the app hides every scanner entry point, so an old server just looks unchanged. The endpoint is additive and the API stays `v1`.

**Server.** `internal/app/product` validates the barcode (GTIN-8, 12, 13 or 14 with a correct check digit; UPC-A becomes EAN-13) and keeps a bounded in-memory LRU (found: `products.cache_ttl`, default 24 h; not found: 10 min; failures are never cached). `internal/productsource/openfoodfacts` reads the OFF v2 API with an explicit timeout, a 1 MiB body limit and a field filter. OFF data is entered by volunteers, so anything implausible is treated as "no usable data": no energy value (kcal, or kJ converted), energy above 900 kcal or a macro above 100 g per 100 g (the typical kJ-typed-as-kcal error), macros adding up to more than 105 g, or a value that is not a number. Names and brands are stripped of control characters and length-limited. Lookups have their own rate limit (`limits.product_rate_*`, default 60/min, burst 10) because scanning several products in a row is normal and they cost no AI call. `products.enabled: false` removes the route and the config flag. The barcode reveals what someone eats, so it is never logged: the access log carries the route pattern, and the source client strips the URL from its errors.

**Client.** A scanner screen reads EAN-13, EAN-8 and UPC-A with `mobile_scanner` (on-device Google ML Kit; BSD-3, no extra Dart dependencies) or takes the digits by hand, which is also the way in when the camera is not allowed. Codes that fail the check digit (misreads) are dropped silently before anything is sent. The found product is shown with its nutrition and the attribution "Nutrition data: Open Food Facts (ODbL)", then added like any food from the search: the declared serving is the default quantity, and the item is a manual one with `nutritionSource: packaged`. Entry points: "Scan barcode" in the add sheet (a new meal with just that product: no plate photo) and a scan button in the food search of the meal editor.

**Local cache.** A product found online is stored in the `foods` table (`source = packaged`, `sourceId` = barcode, the digits as an alias, the serving in `gramsPerPortion`), so scanning it again works offline and the food search finds it by name or by number. There is no schema change or migration. The cache is never refreshed automatically; "Clear all data" removes it.

## Consequences

* The barcode number is sent to the CalSnap server, which asks OFF; the privacy note and the in-app privacy text say so. Nothing else is added to the request.
* The scanner library brings Google ML Kit into the app (about +5 MB per ABI, the merged manifest gains `ACCESS_NETWORK_STATE`). ML Kit reads the barcode on the device, but it may report anonymous technical usage metrics to Google; the app cannot switch that off. A pure-Dart decoder on the camera preview stream would avoid it at the cost of speed and reliability.
* Open Food Facts data is only as good as its contributors. The plausibility checks remove obvious errors, not subtle ones (a wrong protein value that still adds up). The result screen shows the values before they are added, and every value stays editable in the meal editor.
* ODbL attribution is shown in the app and documented in the README; operators who redistribute the data must follow the licence.
* Products OFF knows without nutrition data are reported as not found; the user is pointed to "custom product" in the food search.
