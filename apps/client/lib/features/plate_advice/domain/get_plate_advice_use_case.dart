import '../../balanced_plate/domain/plate_analysis.dart';
import '../../meal/domain/meal_draft.dart';
import 'plate_advice.dart';
import 'plate_advice_repository.dart';
import 'plate_advice_request.dart';

/// Builds a plate advice request from the current draft and analysis, and
/// asks the repository for advice.
class GetPlateAdviceUseCase {
  GetPlateAdviceUseCase(this._repository);

  final PlateAdviceRepository _repository;

  /// Throws [StateError] when [analysis] is not evaluable; the UI never
  /// offers plate advice in that state, so reaching this is a caller bug.
  Future<PlateAdvice> execute({
    required MealDraft draft,
    required PlateAnalysis analysis,
    required String locale,
    Future<void>? cancel,
  }) {
    final request = PlateAdviceRequest.tryCreate(
      draft: draft,
      analysis: analysis,
      locale: locale,
    );
    if (request == null) {
      throw StateError(
        'GetPlateAdviceUseCase.execute called with a non-evaluable analysis.',
      );
    }
    return _repository.getAdvice(request, cancel: cancel);
  }
}
