import '../../balanced_plate/domain/balanced_plate_analyzer.dart';
import '../../balanced_plate/domain/plate_analysis.dart';
import '../../balanced_plate/domain/plate_group.dart';
import '../../meal/domain/meal_draft.dart';

/// Per-dimension plate-balance quality, mirroring the backend's
/// `PlateBalanceStatus` (`protocol/api/openapi.yaml`).
enum BalanceStatus {
  low,
  ok,
  high,
  unknown;

  String get wireName => switch (this) {
    BalanceStatus.low => 'low',
    BalanceStatus.ok => 'ok',
    BalanceStatus.high => 'high',
    BalanceStatus.unknown => 'unknown',
  };
}

/// The local plate-balance assessment reduced to what the backend needs: the
/// per-dimension status, derived from the same thresholds as the local card
/// (design.md Decision 11). Lives in the client feature, not the analyzer, so
/// the balanced-plate engine itself stays untouched.
class PlateBalanceSnapshot {
  const PlateBalanceSnapshot({
    required this.vegetablesFruit,
    required this.protein,
    required this.complexCarbohydrates,
  });

  /// [analysis] must be analyzable; callers check that before calling this.
  factory PlateBalanceSnapshot.fromAnalysis(PlateAnalysis analysis) {
    final vegetablesFruit =
        analysis.vegetableFruitRatio < PlateThresholds.lowVegetableFruitRatio
        ? BalanceStatus.low
        : BalanceStatus.ok;
    final protein = analysis.proteinRatio < PlateThresholds.lowProteinRatio
        ? BalanceStatus.low
        : BalanceStatus.ok;
    final BalanceStatus complexCarbohydrates;
    if (analysis.complexCarbohydrateRatio >
        PlateThresholds.carbohydrateDominanceRatio) {
      complexCarbohydrates = BalanceStatus.high;
    } else if (analysis.complexCarbohydrateRatio <
        PlateThresholds.lowComplexCarbohydrateRatio) {
      complexCarbohydrates = BalanceStatus.low;
    } else {
      complexCarbohydrates = BalanceStatus.ok;
    }
    return PlateBalanceSnapshot(
      vegetablesFruit: vegetablesFruit,
      protein: protein,
      complexCarbohydrates: complexCarbohydrates,
    );
  }

  final BalanceStatus vegetablesFruit;
  final BalanceStatus protein;
  final BalanceStatus complexCarbohydrates;

  Map<String, dynamic> toJson() => {
    'vegetablesFruit': vegetablesFruit.wireName,
    'protein': protein.wireName,
    'complexCarbohydrates': complexCarbohydrates.wireName,
  };
}

/// One item of a plate advice request.
class PlateAdviceItem {
  const PlateAdviceItem({
    required this.name,
    required this.weightG,
    required this.plateGroup,
  });

  final String name;
  final double weightG;
  final PlateGroup plateGroup;

  Map<String, dynamic> toJson() => {
    'name': name,
    'weightG': weightG,
    'plateGroup': plateGroup.wireName,
  };
}

/// Maximum item name length the backend accepts (after normalization there,
/// but the client already keeps names within it so nothing is silently cut
/// server-side).
const int _maxItemNameRunes = 120;

/// Maximum number of items a request may carry; the heaviest are kept.
const int _maxItems = 30;

/// A validated, minimal `POST /v1/plate-advice` request built from the
/// current draft and its local analysis. See spec's "The request carries
/// only the minimal data" requirement.
class PlateAdviceRequest {
  const PlateAdviceRequest({
    required this.locale,
    required this.mealType,
    required this.items,
    required this.balance,
  });

  /// Returns null when the analysis is not evaluable (spec: "no request can
  /// be created"). Otherwise drops non-positive-weight items, truncates names
  /// to 120 runes, and keeps the 30 heaviest items (stable by original order
  /// on a weight tie).
  static PlateAdviceRequest? tryCreate({
    required MealDraft draft,
    required PlateAnalysis analysis,
    required String locale,
  }) {
    if (!analysis.isAnalyzable) return null;

    final positive = <MapEntry<int, PlateAdviceItem>>[
      for (var i = 0; i < draft.items.length; i++)
        if (draft.items[i].weightG > 0)
          MapEntry(
            i,
            PlateAdviceItem(
              name: _truncate(draft.items[i].name, _maxItemNameRunes),
              weightG: draft.items[i].weightG,
              plateGroup: draft.items[i].plateGroup,
            ),
          ),
    ];
    // A manual, stable sort by weight descending: List.sort does not
    // guarantee stability, and the spec requires ties to keep their order.
    positive.sort((a, b) {
      final byWeight = b.value.weightG.compareTo(a.value.weightG);
      if (byWeight != 0) return byWeight;
      return a.key.compareTo(b.key);
    });
    final items = positive.take(_maxItems).map((e) => e.value).toList();

    return PlateAdviceRequest(
      locale: locale,
      mealType: draft.mealType.name,
      items: items,
      balance: PlateBalanceSnapshot.fromAnalysis(analysis),
    );
  }

  final String locale;
  final String mealType;
  final List<PlateAdviceItem> items;
  final PlateBalanceSnapshot balance;

  Map<String, dynamic> toJson() => {
    'locale': locale,
    'mealType': mealType,
    'items': [for (final item in items) item.toJson()],
    'balance': balance.toJson(),
  };

  /// A canonical string that changes exactly when the request's meaning
  /// changes: items sorted by (name, whole-gram weight, group), then the
  /// balance, the locale and the meal type. Used to detect a stale request
  /// (design.md Decision 11); a plain string compare is enough.
  String get fingerprint {
    final sorted = [...items]
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        final byWeight = a.weightG.round().compareTo(b.weightG.round());
        if (byWeight != 0) return byWeight;
        return a.plateGroup.wireName.compareTo(b.plateGroup.wireName);
      });
    final itemsPart = sorted
        .map((i) => '${i.name}|${i.weightG.round()}|${i.plateGroup.wireName}')
        .join(';');
    final balancePart =
        '${balance.vegetablesFruit.wireName},${balance.protein.wireName},'
        '${balance.complexCarbohydrates.wireName}';
    return '$itemsPart#$balancePart#$locale#$mealType';
  }
}

String _truncate(String s, int maxRunes) {
  final runes = s.runes.toList();
  if (runes.length <= maxRunes) return s;
  return String.fromCharCodes(runes.take(maxRunes));
}
