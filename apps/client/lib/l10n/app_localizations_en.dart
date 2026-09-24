// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CalSnap';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get apply => 'Apply';

  @override
  String get edit => 'Edit';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get create => 'Create';

  @override
  String get gramsUnit => 'g';

  @override
  String get unitGram => 'g';

  @override
  String get unitMilliliter => 'ml';

  @override
  String get unitPiece => 'pcs';

  @override
  String get unitPortion => 'portion';

  @override
  String get proteinLabel => 'Protein';

  @override
  String get fatLabel => 'Fat';

  @override
  String get carbsLabel => 'Carbs';

  @override
  String get mealBreakfast => 'Breakfast';

  @override
  String get mealLunch => 'Lunch';

  @override
  String get mealDinner => 'Dinner';

  @override
  String get mealSnack => 'Snack';

  @override
  String get mealOther => 'Other';

  @override
  String get mealUnnamed => 'Meal';

  @override
  String get navDiary => 'Diary';

  @override
  String get navHistory => 'History';

  @override
  String get navStatistics => 'Statistics';

  @override
  String get navSettings => 'Settings';

  @override
  String get initErrorTitle => 'CalSnap could not start';

  @override
  String get initErrorBody =>
      'Something went wrong while opening your diary. Your data has not been changed. Please try again.';

  @override
  String get unsupportedSchemaTitle => 'Please update CalSnap';

  @override
  String get unsupportedSchemaBody =>
      'Your diary was created by a newer version of the app. Update CalSnap to open it. Your data has not been changed.';

  @override
  String onboardingStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingIntroTitle => 'Log meals with a photo';

  @override
  String get onboardingIntroBody =>
      'Take a photo of your meal, check the foods CalSnap finds, and save. Your diary stays on this device.';

  @override
  String get onboardingEstimateNotice =>
      'Calories from photos are estimates, not exact measurements. You can correct every value.';

  @override
  String get onboardingTargetTitle => 'Daily calorie target';

  @override
  String get onboardingTargetHint => 'kcal per day';

  @override
  String get errKcalRange => 'Enter a value from 800 to 6000 kcal.';

  @override
  String get onboardingMacrosTitle => 'Macro targets (optional)';

  @override
  String get onboardingMacrosBody =>
      'Grams per day. Leave a field empty if you do not track it.';

  @override
  String get errMacroRange => 'Enter 0 to 500 g or leave the field empty.';

  @override
  String get proteinFieldLabel => 'Protein, g';

  @override
  String get fatFieldLabel => 'Fat, g';

  @override
  String get carbsFieldLabel => 'Carbs, g';

  @override
  String get onboardingPlateTitle => 'Plate diameter (optional)';

  @override
  String get onboardingPlateBody =>
      'Helps to estimate portion sizes from photos. Typical dinner plates are 24 to 28 cm.';

  @override
  String get plateFieldLabel => 'Diameter, cm';

  @override
  String get errPlateRange =>
      'Enter a value from 10 to 40 cm or leave the field empty.';

  @override
  String get onboardingCameraTitle => 'Camera access';

  @override
  String get onboardingCameraBody =>
      'CalSnap uses the camera to photograph your meals. You can also pick photos from the gallery or add meals manually.';

  @override
  String get allowCamera => 'Allow camera';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String kcalProgress(String consumed, String target) {
    return '$consumed / $target kcal';
  }

  @override
  String kcalConsumedOnly(String consumed) {
    return '$consumed kcal';
  }

  @override
  String kcalRemaining(String amount) {
    return '$amount kcal remaining';
  }

  @override
  String kcalOver(String amount) {
    return '$amount kcal over the target';
  }

  @override
  String macroProgress(String consumed, String target) {
    return '$consumed / $target g';
  }

  @override
  String macroConsumed(String consumed) {
    return '$consumed g';
  }

  @override
  String get emptyDayTitle => 'No meals yet';

  @override
  String get emptyDayBody => 'Take a photo of your meal or add it manually.';

  @override
  String get addMeal => 'Add';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';

  @override
  String get addManually => 'Add manually';

  @override
  String get previousDay => 'Previous day';

  @override
  String get nextDay => 'Next day';

  @override
  String get openCalendar => 'Open calendar';

  @override
  String get historyTitle => 'History';

  @override
  String get historyHint => 'Days with meals are marked. Tap a day to open it.';

  @override
  String get mealPhoto => 'Meal photo';

  @override
  String get captureTitle => 'Take a photo';

  @override
  String get cameraPermissionTitle => 'Camera access is needed';

  @override
  String get cameraPermissionBody =>
      'CalSnap needs the camera to photograph your meal. You can still choose a photo from the gallery or add the meal manually.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get cameraUnavailable =>
      'The camera is not available. You can choose a photo from the gallery instead.';

  @override
  String get flashOff => 'Flash off';

  @override
  String get flashAuto => 'Flash auto';

  @override
  String get flashOn => 'Flash on';

  @override
  String get switchCamera => 'Switch camera';

  @override
  String get shutter => 'Take photo';

  @override
  String get gallery => 'Gallery';

  @override
  String get retake => 'Retake';

  @override
  String get analyze => 'Analyze';

  @override
  String get previewTitle => 'Check the photo';

  @override
  String get imageUnreadable => 'This image cannot be read. Try another photo.';

  @override
  String get imageTooLarge =>
      'This photo is too large to upload. Try another photo.';

  @override
  String get analyzingTitle => 'Analyzing your meal…';

  @override
  String get stepPreparing => 'Preparing the photo';

  @override
  String get stepIdentifying => 'Identifying foods';

  @override
  String get stepPortions => 'Estimating portions';

  @override
  String get stepNutrition => 'Calculating nutrition';

  @override
  String get errOffline =>
      'No internet connection. The diary is available offline. Analyzing a new photo requires a network.';

  @override
  String get errTimeout => 'The analysis is taking too long. Please try again.';

  @override
  String get errRateLimited =>
      'Too many requests. Please try again in a little while.';

  @override
  String get errUnavailable =>
      'The analysis service is temporarily unavailable. Please try again.';

  @override
  String get errNotRecognized => 'Could not confidently recognize the dish.';

  @override
  String get errBadImage => 'This photo cannot be analyzed. Try another photo.';

  @override
  String get errUnknown => 'Something went wrong. Please try again.';

  @override
  String get tryAnotherPhoto => 'Try another photo';

  @override
  String get resultTitle => 'Recognized';

  @override
  String get editMealTitle => 'Edit meal';

  @override
  String get newMealTitle => 'New meal';

  @override
  String get estimateNotice =>
      'Weights are estimates. Please check them before saving.';

  @override
  String get improveAccuracy => 'Improve accuracy';

  @override
  String get improveAccuracyHint =>
      'A second photo from the side helps with rice, pasta, potatoes, salads, cakes and meat.';

  @override
  String get twoPhotoNote => 'Estimated from two photos.';

  @override
  String get sideCaptureTitle => 'Side photo';

  @override
  String get sideCaptureHint =>
      'Hold the camera at plate level and photograph the meal from the side.';

  @override
  String get replaceEditsTitle => 'Replace your changes?';

  @override
  String get replaceEditsBody =>
      'The new estimate replaces the items and weights you have edited. Your first result stays if you cancel.';

  @override
  String get replaceEditsAction => 'Continue';

  @override
  String get keepFirstResult => 'Keep the first result';

  @override
  String approxKcal(String value) {
    return '$value kcal';
  }

  @override
  String totalKcal(String value) {
    return '$value kcal';
  }

  @override
  String get estimatedWeight => 'estimate';

  @override
  String get personalizedWeight => 'adjusted';

  @override
  String personalizedWeightNote(String weight) {
    return 'AI estimated $weight g. Adjusted to your usual portions.';
  }

  @override
  String get pleaseCheck => 'Please check';

  @override
  String get partialBanner =>
      'Some ingredients may have been missed. Check the result before saving.';

  @override
  String get estimatedNutritionNote =>
      'Nutrition values for this item are estimated.';

  @override
  String get addItem => 'Add item';

  @override
  String get mealTypeFieldLabel => 'Meal type';

  @override
  String get noItemsHint => 'Add at least one item to save.';

  @override
  String get removeItem => 'Remove';

  @override
  String get editItemTitle => 'Edit item';

  @override
  String get itemNameLabel => 'Name';

  @override
  String get itemWeightLabel => 'Weight';

  @override
  String get per100Title => 'Per 100 g';

  @override
  String get kcalPer100Label => 'kcal per 100 g';

  @override
  String get errWeightRange => 'Enter a weight above 0 and up to 5000 g.';

  @override
  String get errNameRequired => 'Enter a name (up to 100 characters).';

  @override
  String get errKcal900 => 'Calories must be between 0 and 900 per 100 g.';

  @override
  String get errMacro100 => 'Each value must be between 0 and 100 g.';

  @override
  String weightInGrams(String grams) {
    return '= $grams g';
  }

  @override
  String get replaceProduct => 'Replace product';

  @override
  String get discardTitle => 'Discard changes?';

  @override
  String get discardBody => 'Your changes have not been saved.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get deleteMealTitle => 'Delete this meal?';

  @override
  String get deleteMealBody => 'The meal and its photo will be removed.';

  @override
  String get mealDeleted => 'Meal deleted';

  @override
  String get undo => 'Undo';

  @override
  String get emptyMealTitle => 'The meal has no items';

  @override
  String get emptyMealBody =>
      'A meal needs at least one item. You can delete the meal instead.';

  @override
  String get deleteMeal => 'Delete meal';

  @override
  String get mealSaved => 'Meal saved';

  @override
  String get saveFailed =>
      'The meal could not be saved. Your entries are kept, please try again.';

  @override
  String get searchFoodsTitle => 'Add food';

  @override
  String get searchHint => 'Search foods';

  @override
  String get noResults => 'No foods found.';

  @override
  String get createCustomProduct => 'Create custom product';

  @override
  String get customProductTitle => 'New product';

  @override
  String get statsTitle => 'Last 7 days';

  @override
  String get statsToday => 'Today';

  @override
  String get statsAverage => 'Average per logged day';

  @override
  String statsAdherence(int onTarget, int logged) {
    String _temp0 = intl.Intl.pluralLogic(
      logged,
      locale: localeName,
      other: '$logged logged days',
      one: '$logged logged day',
    );
    return '$onTarget of $_temp0 on target';
  }

  @override
  String get statsNoData => 'No meals logged in the last 7 days.';

  @override
  String statsTarget(String value) {
    return 'Target $value kcal';
  }

  @override
  String get statsChartLabel => 'Calories per day for the last 7 days';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTargetsSection => 'Daily targets';

  @override
  String get settingsCalories => 'Calorie target';

  @override
  String get settingsPlate => 'My usual plate';

  @override
  String get scanBarcode => 'Scan barcode';

  @override
  String get scanLabelButton => 'Scan nutrition label';

  @override
  String get scanSourceUser => 'Saved by you';

  @override
  String get labelScanTitle => 'Nutrition label';

  @override
  String get labelHint =>
      'Fill the frame with the nutrition table. Keep it straight, sharp and well lit.';

  @override
  String get labelRead => 'Read label';

  @override
  String get labelNotRecognized =>
      'No nutrition table was found in this photo. Photograph the table straight on and in focus, or enter the values yourself.';

  @override
  String get labelFillButton => 'Fill from a label photo';

  @override
  String get labelCheckValues =>
      'Check every value against the package before saving.';

  @override
  String get labelConverted =>
      'The label was per serving; the values were converted to 100 g.';

  @override
  String get labelVolume =>
      'The label was per 100 ml; the values are used as per 100 g.';

  @override
  String get labelEnergyMismatch =>
      'The energy does not match the protein, fat and carbohydrates. Please check the numbers.';

  @override
  String get labelEnergyEstimated =>
      'The label showed no energy; it was calculated from protein, fat and carbohydrates.';

  @override
  String get labelLowConfidence =>
      'The text was hard to read. Some numbers may be wrong.';

  @override
  String get labelIncomplete =>
      'Some values could not be read. Please fill them in.';

  @override
  String customBarcode(String value) {
    return 'Barcode $value';
  }

  @override
  String get customServingLabel => 'Serving, g (optional)';

  @override
  String get errServing =>
      'Enter a serving from 1 to 2000 g or leave the field empty.';

  @override
  String get scanTitle => 'Scan barcode';

  @override
  String get scanHint => 'Point the camera at the barcode on the package';

  @override
  String get scanTorch => 'Flashlight';

  @override
  String get scanCameraError =>
      'The camera cannot be used. You can type the barcode number below.';

  @override
  String get scanPermissionBody =>
      'Camera access is needed to scan barcodes. You can also type the number below.';

  @override
  String get scanManualLabel => 'Barcode number';

  @override
  String get scanManualInvalid =>
      'Enter a valid barcode: 8, 12, 13 or 14 digits.';

  @override
  String get scanFind => 'Find';

  @override
  String get scanLooking => 'Looking up the product…';

  @override
  String get scanNotFound =>
      'No nutrition data was found for this product. You can add it as a custom product in the food search.';

  @override
  String get scanAnother => 'Scan another';

  @override
  String get scanSource => 'Nutrition data: Open Food Facts (ODbL)';

  @override
  String scanServing(String value) {
    return 'Serving: $value g';
  }

  @override
  String get plateGuideHint => 'Hold the camera directly above the plate';

  @override
  String get qualityTitle => 'Retake for a better estimate?';

  @override
  String get issueSteepAngle =>
      'The plate is shot at a steep angle. For a more accurate portion estimate, take the photo from above.';

  @override
  String get issuePlateCutOff =>
      'The plate does not fit in the frame. Step back a little so the whole plate is visible.';

  @override
  String get issueBlurry =>
      'The photo looks blurry. Hold the phone steady and let it focus.';

  @override
  String get issueTooDark =>
      'The photo is too dark. Move to better light or turn on the flash.';

  @override
  String get issueTooBright =>
      'The photo is overexposed. Avoid glare and direct light.';

  @override
  String plateChipUsual(String value) {
    return 'My usual plate: $value cm';
  }

  @override
  String plateChipOnce(String value) {
    return 'Plate for this photo: $value cm';
  }

  @override
  String get plateChipAdd => 'Add plate size';

  @override
  String get plateSheetTitle => 'Plate size';

  @override
  String get plateSheetBody =>
      'A known plate size helps to estimate the portion. Typical dinner plates are 24 to 28 cm.';

  @override
  String get plateOtherLabel => 'Other, cm';

  @override
  String get plateRemember => 'Remember as my usual plate';

  @override
  String get plateNone => 'No plate size';

  @override
  String get notSet => 'Not set';

  @override
  String get settingsPhotosSection => 'Photos';

  @override
  String get settingsSavePhotos => 'Save meal photos';

  @override
  String get settingsSavePhotosHint =>
      'When off, photos are deleted after the analysis. Existing photos are kept.';

  @override
  String get settingsPersonalizePortions => 'Adapt weights to my corrections';

  @override
  String get settingsPersonalizePortionsHint =>
      'Learns from the weights you change and adjusts later estimates. Everything stays on this device.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get settingsDataSection => 'Your data';

  @override
  String get settingsExportCsv => 'Export CSV';

  @override
  String get settingsExportJson => 'Export JSON';

  @override
  String get exportFailed => 'The export failed. Please try again.';

  @override
  String get exportSubject => 'CalSnap export';

  @override
  String get settingsClearData => 'Clear all data';

  @override
  String get clearDataTitle => 'Clear all data?';

  @override
  String get clearDataBody =>
      'This permanently deletes all meals, photos, custom products and settings from this device. It cannot be undone. Consider exporting your data first.';

  @override
  String get clearDataConfirm => 'Delete everything';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String valueUnitKcal(String value) {
    return '$value kcal';
  }

  @override
  String valueUnitGrams(String value) {
    return '$value g';
  }

  @override
  String valueUnitCm(String value) {
    return '$value cm';
  }

  @override
  String get privacyTitle => 'Privacy';

  @override
  String get privacyDiary => 'Your diary is stored only on this device.';

  @override
  String get privacyAnalysis =>
      'When you analyze a photo, CalSnap sends the prepared photo (without metadata; two photos if you add a side photo, or a photo of a nutrition label if you scan one), the app language and, if set, your plate diameter to the CalSnap server, which forwards them to an AI provider.';

  @override
  String get privacyBarcode =>
      'Barcodes are read on your device. To find a product, CalSnap sends only the barcode number to its server, which asks Open Food Facts. The scanner library may send anonymous technical statistics to Google.';

  @override
  String get privacyNoStorage =>
      'The CalSnap server does not store your photos after the request is finished.';

  @override
  String get privacyProvider =>
      'The retention and training terms of the AI provider apply to what it receives.';

  @override
  String get privacyPolicyLink => 'Full privacy policy';

  @override
  String get privacyPolicyUnavailable => 'The link could not be opened.';

  @override
  String get settingsServerSection => 'Server';

  @override
  String get settingsServerUrl => 'Server address';

  @override
  String get serverUrlHelp =>
      'Address of your CalSnap server, for example https://calsnap.example.com. Leave empty to use the default.';

  @override
  String get errServerUrlInvalid =>
      'Enter a full address that starts with https://, without a login, query or #fragment.';

  @override
  String get errServerUrlInsecure =>
      'Only secure https:// addresses are allowed.';

  @override
  String get errServerNotConfigured =>
      'The server address is not set. Enter the address of your CalSnap server in the settings to analyze photos.';

  @override
  String get serverSettingsAction => 'Server settings';

  @override
  String get errCertificate =>
      'The server\'s security certificate is not trusted or has changed. Open the server settings and review it.';

  @override
  String get serverCheckingCertificate => 'Checking the server…';

  @override
  String get serverCertificateTrusted => 'Self-signed certificate confirmed';

  @override
  String get certTrustTitle => 'Trust this server?';

  @override
  String get certChangedTitle => 'Server certificate changed';

  @override
  String certTrustBody(String host) {
    return 'The server $host uses a certificate that this device does not recognize, most likely a self-signed one. Compare the fingerprint below with the one in the server log. Trust the server only if they are identical.';
  }

  @override
  String certChangedBody(String host) {
    return 'The certificate of $host is not the one you confirmed earlier. That is expected if the server generated a new certificate. Otherwise someone may be intercepting the connection. Compare the fingerprint with the server log before trusting it.';
  }

  @override
  String get certFingerprintLabel => 'SHA-256 fingerprint';

  @override
  String get certSubjectLabel => 'Subject';

  @override
  String certValidUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String get certTrustAction => 'Trust';
}
