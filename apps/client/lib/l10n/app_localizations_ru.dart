// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'CalSnap';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get delete => 'Удалить';

  @override
  String get retry => 'Повторить';

  @override
  String get close => 'Закрыть';

  @override
  String get apply => 'Применить';

  @override
  String get edit => 'Изменить';

  @override
  String get next => 'Далее';

  @override
  String get back => 'Назад';

  @override
  String get skip => 'Пропустить';

  @override
  String get create => 'Создать';

  @override
  String get gramsUnit => 'г';

  @override
  String get unitGram => 'г';

  @override
  String get unitMilliliter => 'мл';

  @override
  String get unitPiece => 'шт';

  @override
  String get unitPortion => 'порция';

  @override
  String get proteinLabel => 'Белки';

  @override
  String get fatLabel => 'Жиры';

  @override
  String get carbsLabel => 'Углеводы';

  @override
  String get mealBreakfast => 'Завтрак';

  @override
  String get mealLunch => 'Обед';

  @override
  String get mealDinner => 'Ужин';

  @override
  String get mealSnack => 'Перекус';

  @override
  String get mealOther => 'Другое';

  @override
  String get mealUnnamed => 'Приём пищи';

  @override
  String get navDiary => 'Дневник';

  @override
  String get navHistory => 'История';

  @override
  String get navStatistics => 'Статистика';

  @override
  String get navSettings => 'Настройки';

  @override
  String get initErrorTitle => 'Не удалось запустить CalSnap';

  @override
  String get initErrorBody =>
      'Не удалось открыть дневник. Ваши данные не изменены. Попробуйте ещё раз.';

  @override
  String get unsupportedSchemaTitle => 'Обновите CalSnap';

  @override
  String get unsupportedSchemaBody =>
      'Ваш дневник создан более новой версией приложения. Обновите CalSnap, чтобы открыть его. Данные не изменены.';

  @override
  String onboardingStep(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String get onboardingIntroTitle => 'Записывайте еду по фото';

  @override
  String get onboardingIntroBody =>
      'Сфотографируйте блюдо, проверьте найденные продукты и сохраните. Дневник хранится только на этом устройстве.';

  @override
  String get onboardingEstimateNotice =>
      'Калории по фото — это оценка, а не точное измерение. Каждое значение можно исправить.';

  @override
  String get onboardingTargetTitle => 'Дневная цель по калориям';

  @override
  String get onboardingTargetHint => 'ккал в день';

  @override
  String get errKcalRange => 'Введите значение от 800 до 6000 ккал.';

  @override
  String get onboardingMacrosTitle => 'Цели по БЖУ (необязательно)';

  @override
  String get onboardingMacrosBody =>
      'Граммы в день. Оставьте поле пустым, если не отслеживаете.';

  @override
  String get errMacroRange => 'Введите от 0 до 500 г или оставьте поле пустым.';

  @override
  String get proteinFieldLabel => 'Белки, г';

  @override
  String get fatFieldLabel => 'Жиры, г';

  @override
  String get carbsFieldLabel => 'Углеводы, г';

  @override
  String get onboardingPlateTitle => 'Диаметр тарелки (необязательно)';

  @override
  String get onboardingPlateBody =>
      'Помогает точнее оценивать порции по фото. Обычные обеденные тарелки — 24–28 см.';

  @override
  String get plateFieldLabel => 'Диаметр, см';

  @override
  String get errPlateRange =>
      'Введите значение от 10 до 40 см или оставьте поле пустым.';

  @override
  String get onboardingCameraTitle => 'Доступ к камере';

  @override
  String get onboardingCameraBody =>
      'CalSnap использует камеру, чтобы фотографировать еду. Также можно выбирать фото из галереи или добавлять еду вручную.';

  @override
  String get allowCamera => 'Разрешить камеру';

  @override
  String get today => 'Сегодня';

  @override
  String get yesterday => 'Вчера';

  @override
  String kcalProgress(String consumed, String target) {
    return '$consumed / $target ккал';
  }

  @override
  String kcalConsumedOnly(String consumed) {
    return '$consumed ккал';
  }

  @override
  String kcalRemaining(String amount) {
    return 'Осталось $amount ккал';
  }

  @override
  String kcalOver(String amount) {
    return 'Выше цели на $amount ккал';
  }

  @override
  String macroProgress(String consumed, String target) {
    return '$consumed / $target г';
  }

  @override
  String macroConsumed(String consumed) {
    return '$consumed г';
  }

  @override
  String get emptyDayTitle => 'Пока нет записей';

  @override
  String get emptyDayBody => 'Сфотографируйте блюдо или добавьте его вручную.';

  @override
  String get addMeal => 'Добавить';

  @override
  String get takePhoto => 'Сфотографировать';

  @override
  String get chooseFromGallery => 'Выбрать из галереи';

  @override
  String get addManually => 'Добавить вручную';

  @override
  String get previousDay => 'Предыдущий день';

  @override
  String get nextDay => 'Следующий день';

  @override
  String get openCalendar => 'Открыть календарь';

  @override
  String get historyTitle => 'История';

  @override
  String get historyHint =>
      'Дни с записями отмечены. Нажмите на день, чтобы открыть.';

  @override
  String get mealPhoto => 'Фото блюда';

  @override
  String get captureTitle => 'Фото блюда';

  @override
  String get cameraPermissionTitle => 'Нужен доступ к камере';

  @override
  String get cameraPermissionBody =>
      'CalSnap нужна камера, чтобы сфотографировать блюдо. Вы можете выбрать фото из галереи или добавить блюдо вручную.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get cameraUnavailable =>
      'Камера недоступна. Вы можете выбрать фото из галереи.';

  @override
  String get flashOff => 'Вспышка выкл.';

  @override
  String get flashAuto => 'Вспышка авто';

  @override
  String get flashOn => 'Вспышка вкл.';

  @override
  String get switchCamera => 'Сменить камеру';

  @override
  String get shutter => 'Сделать снимок';

  @override
  String get gallery => 'Галерея';

  @override
  String get retake => 'Переснять';

  @override
  String get analyze => 'Анализировать';

  @override
  String get previewTitle => 'Проверьте фото';

  @override
  String get imageUnreadable =>
      'Не удаётся прочитать это изображение. Попробуйте другое фото.';

  @override
  String get imageTooLarge =>
      'Фото слишком большое для отправки. Попробуйте другое.';

  @override
  String get analyzingTitle => 'Анализируем блюдо…';

  @override
  String get stepPreparing => 'Готовим фото';

  @override
  String get stepIdentifying => 'Определяем продукты';

  @override
  String get stepPortions => 'Оцениваем размер порций';

  @override
  String get stepNutrition => 'Рассчитываем пищевую ценность';

  @override
  String get errOffline =>
      'Нет подключения к интернету. Дневник доступен офлайн. Для анализа нового фото нужна сеть.';

  @override
  String get errTimeout =>
      'Анализ занимает слишком много времени. Попробуйте ещё раз.';

  @override
  String get errRateLimited => 'Слишком много запросов. Попробуйте чуть позже.';

  @override
  String get errUnavailable =>
      'Сервис анализа временно недоступен. Попробуйте ещё раз.';

  @override
  String get errNotRecognized => 'Не удалось уверенно распознать блюдо.';

  @override
  String get errBadImage =>
      'Это фото невозможно проанализировать. Попробуйте другое.';

  @override
  String get errUnknown => 'Что-то пошло не так. Попробуйте ещё раз.';

  @override
  String get tryAnotherPhoto => 'Попробовать другое фото';

  @override
  String get resultTitle => 'Распознано';

  @override
  String get editMealTitle => 'Редактирование';

  @override
  String get newMealTitle => 'Новый приём пищи';

  @override
  String get estimateNotice =>
      'Вес — это оценка. Проверьте значения перед сохранением.';

  @override
  String approxKcal(String value) {
    return '$value ккал';
  }

  @override
  String totalKcal(String value) {
    return '$value ккал';
  }

  @override
  String get estimatedWeight => 'оценка';

  @override
  String get pleaseCheck => 'Проверьте';

  @override
  String get partialBanner =>
      'Некоторые ингредиенты могли быть пропущены. Проверьте результат перед сохранением.';

  @override
  String get estimatedNutritionNote =>
      'Пищевая ценность этого продукта оценена приблизительно.';

  @override
  String get addItem => 'Добавить продукт';

  @override
  String get mealTypeFieldLabel => 'Тип приёма пищи';

  @override
  String get noItemsHint => 'Добавьте хотя бы один продукт, чтобы сохранить.';

  @override
  String get removeItem => 'Убрать';

  @override
  String get editItemTitle => 'Изменить продукт';

  @override
  String get itemNameLabel => 'Название';

  @override
  String get itemWeightLabel => 'Вес';

  @override
  String get per100Title => 'На 100 г';

  @override
  String get kcalPer100Label => 'ккал на 100 г';

  @override
  String get errWeightRange => 'Введите вес больше 0 и не более 5000 г.';

  @override
  String get errNameRequired => 'Введите название (до 100 символов).';

  @override
  String get errKcal900 => 'Калорийность должна быть от 0 до 900 на 100 г.';

  @override
  String get errMacro100 => 'Каждое значение должно быть от 0 до 100 г.';

  @override
  String weightInGrams(String grams) {
    return '= $grams г';
  }

  @override
  String get replaceProduct => 'Заменить продукт';

  @override
  String get discardTitle => 'Отменить изменения?';

  @override
  String get discardBody => 'Изменения не сохранены.';

  @override
  String get discard => 'Отменить';

  @override
  String get keepEditing => 'Продолжить';

  @override
  String get deleteMealTitle => 'Удалить этот приём пищи?';

  @override
  String get deleteMealBody => 'Приём пищи и его фото будут удалены.';

  @override
  String get mealDeleted => 'Приём пищи удалён';

  @override
  String get undo => 'Отменить';

  @override
  String get emptyMealTitle => 'В приёме пищи нет продуктов';

  @override
  String get emptyMealBody =>
      'Нужен хотя бы один продукт. Вместо этого можно удалить приём пищи.';

  @override
  String get deleteMeal => 'Удалить приём пищи';

  @override
  String get mealSaved => 'Приём пищи сохранён';

  @override
  String get saveFailed =>
      'Не удалось сохранить. Введённые данные сохранены в форме, попробуйте ещё раз.';

  @override
  String get searchFoodsTitle => 'Добавить продукт';

  @override
  String get searchHint => 'Поиск продуктов';

  @override
  String get noResults => 'Продукты не найдены.';

  @override
  String get createCustomProduct => 'Создать свой продукт';

  @override
  String get customProductTitle => 'Новый продукт';

  @override
  String get statsTitle => 'Последние 7 дней';

  @override
  String get statsToday => 'Сегодня';

  @override
  String get statsAverage => 'В среднем за день с записями';

  @override
  String statsAdherence(int onTarget, int logged) {
    String _temp0 = intl.Intl.pluralLogic(
      logged,
      locale: localeName,
      other: '$logged записанных дней',
      one: '$logged записанного дня',
    );
    return '$onTarget из $_temp0 в пределах цели';
  }

  @override
  String get statsNoData => 'За последние 7 дней нет записей.';

  @override
  String statsTarget(String value) {
    return 'Цель $value ккал';
  }

  @override
  String get statsChartLabel => 'Калории по дням за последние 7 дней';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsTargetsSection => 'Дневные цели';

  @override
  String get settingsCalories => 'Цель по калориям';

  @override
  String get settingsPlate => 'Диаметр тарелки';

  @override
  String get notSet => 'Не задано';

  @override
  String get settingsPhotosSection => 'Фотографии';

  @override
  String get settingsSavePhotos => 'Сохранять фото блюд';

  @override
  String get settingsSavePhotosHint =>
      'Если выключено, фото удаляются после анализа. Уже сохранённые фото остаются.';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsDataSection => 'Ваши данные';

  @override
  String get settingsExportCsv => 'Экспорт в CSV';

  @override
  String get settingsExportJson => 'Экспорт в JSON';

  @override
  String get exportFailed =>
      'Не удалось выполнить экспорт. Попробуйте ещё раз.';

  @override
  String get exportSubject => 'Экспорт CalSnap';

  @override
  String get settingsClearData => 'Удалить все данные';

  @override
  String get clearDataTitle => 'Удалить все данные?';

  @override
  String get clearDataBody =>
      'Будут безвозвратно удалены все записи, фото, свои продукты и настройки с этого устройства. Это действие нельзя отменить. Сначала можно сделать экспорт данных.';

  @override
  String get clearDataConfirm => 'Удалить всё';

  @override
  String get settingsPrivacy => 'Конфиденциальность';

  @override
  String get settingsAbout => 'О приложении';

  @override
  String settingsVersion(String version) {
    return 'Версия $version';
  }

  @override
  String valueUnitKcal(String value) {
    return '$value ккал';
  }

  @override
  String valueUnitGrams(String value) {
    return '$value г';
  }

  @override
  String valueUnitCm(String value) {
    return '$value см';
  }

  @override
  String get privacyTitle => 'Конфиденциальность';

  @override
  String get privacyDiary => 'Ваш дневник хранится только на этом устройстве.';

  @override
  String get privacyAnalysis =>
      'При анализе фото CalSnap отправляет подготовленное фото (без метаданных), язык приложения и, если задан, диаметр тарелки на сервер CalSnap, который передаёт их AI-провайдеру.';

  @override
  String get privacyNoStorage =>
      'Сервер CalSnap не хранит ваши фото после завершения запроса.';

  @override
  String get privacyProvider =>
      'К данным, полученным AI-провайдером, применяются его условия хранения и обучения.';

  @override
  String get privacyPolicyLink => 'Полная политика конфиденциальности';

  @override
  String get privacyPolicyUnavailable => 'Не удалось открыть ссылку.';
}
