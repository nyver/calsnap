import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CalSnap'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @gramsUnit.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get gramsUnit;

  /// No description provided for @unitGram.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get unitGram;

  /// No description provided for @unitMilliliter.
  ///
  /// In en, this message translates to:
  /// **'ml'**
  String get unitMilliliter;

  /// No description provided for @unitPiece.
  ///
  /// In en, this message translates to:
  /// **'pcs'**
  String get unitPiece;

  /// No description provided for @unitPortion.
  ///
  /// In en, this message translates to:
  /// **'portion'**
  String get unitPortion;

  /// No description provided for @proteinLabel.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get proteinLabel;

  /// No description provided for @fatLabel.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get fatLabel;

  /// No description provided for @carbsLabel.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get carbsLabel;

  /// No description provided for @mealBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get mealBreakfast;

  /// No description provided for @mealLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get mealLunch;

  /// No description provided for @mealDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get mealDinner;

  /// No description provided for @mealSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get mealSnack;

  /// No description provided for @mealOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get mealOther;

  /// No description provided for @mealUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get mealUnnamed;

  /// No description provided for @navDiary.
  ///
  /// In en, this message translates to:
  /// **'Diary'**
  String get navDiary;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get navStatistics;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @initErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'CalSnap could not start'**
  String get initErrorTitle;

  /// No description provided for @initErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while opening your diary. Your data has not been changed. Please try again.'**
  String get initErrorBody;

  /// No description provided for @unsupportedSchemaTitle.
  ///
  /// In en, this message translates to:
  /// **'Please update CalSnap'**
  String get unsupportedSchemaTitle;

  /// No description provided for @unsupportedSchemaBody.
  ///
  /// In en, this message translates to:
  /// **'Your diary was created by a newer version of the app. Update CalSnap to open it. Your data has not been changed.'**
  String get unsupportedSchemaBody;

  /// No description provided for @onboardingStep.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStep(int current, int total);

  /// No description provided for @onboardingIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Log meals with a photo'**
  String get onboardingIntroTitle;

  /// No description provided for @onboardingIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your meal, check the foods CalSnap finds, and save. Your diary stays on this device.'**
  String get onboardingIntroBody;

  /// No description provided for @onboardingEstimateNotice.
  ///
  /// In en, this message translates to:
  /// **'Calories from photos are estimates, not exact measurements. You can correct every value.'**
  String get onboardingEstimateNotice;

  /// No description provided for @onboardingTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily calorie target'**
  String get onboardingTargetTitle;

  /// No description provided for @onboardingTargetHint.
  ///
  /// In en, this message translates to:
  /// **'kcal per day'**
  String get onboardingTargetHint;

  /// No description provided for @errKcalRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from 800 to 6000 kcal.'**
  String get errKcalRange;

  /// No description provided for @onboardingMacrosTitle.
  ///
  /// In en, this message translates to:
  /// **'Macro targets (optional)'**
  String get onboardingMacrosTitle;

  /// No description provided for @onboardingMacrosBody.
  ///
  /// In en, this message translates to:
  /// **'Grams per day. Leave a field empty if you do not track it.'**
  String get onboardingMacrosBody;

  /// No description provided for @errMacroRange.
  ///
  /// In en, this message translates to:
  /// **'Enter 0 to 500 g or leave the field empty.'**
  String get errMacroRange;

  /// No description provided for @proteinFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Protein, g'**
  String get proteinFieldLabel;

  /// No description provided for @fatFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Fat, g'**
  String get fatFieldLabel;

  /// No description provided for @carbsFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Carbs, g'**
  String get carbsFieldLabel;

  /// No description provided for @onboardingPlateTitle.
  ///
  /// In en, this message translates to:
  /// **'Plate diameter (optional)'**
  String get onboardingPlateTitle;

  /// No description provided for @onboardingPlateBody.
  ///
  /// In en, this message translates to:
  /// **'Helps to estimate portion sizes from photos. Typical dinner plates are 24 to 28 cm.'**
  String get onboardingPlateBody;

  /// No description provided for @plateFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Diameter, cm'**
  String get plateFieldLabel;

  /// No description provided for @errPlateRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from 10 to 40 cm or leave the field empty.'**
  String get errPlateRange;

  /// No description provided for @onboardingCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access'**
  String get onboardingCameraTitle;

  /// No description provided for @onboardingCameraBody.
  ///
  /// In en, this message translates to:
  /// **'CalSnap uses the camera to photograph your meals. You can also pick photos from the gallery or add meals manually.'**
  String get onboardingCameraBody;

  /// No description provided for @allowCamera.
  ///
  /// In en, this message translates to:
  /// **'Allow camera'**
  String get allowCamera;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @kcalProgress.
  ///
  /// In en, this message translates to:
  /// **'{consumed} / {target} kcal'**
  String kcalProgress(String consumed, String target);

  /// No description provided for @kcalConsumedOnly.
  ///
  /// In en, this message translates to:
  /// **'{consumed} kcal'**
  String kcalConsumedOnly(String consumed);

  /// No description provided for @kcalRemaining.
  ///
  /// In en, this message translates to:
  /// **'{amount} kcal remaining'**
  String kcalRemaining(String amount);

  /// No description provided for @kcalOver.
  ///
  /// In en, this message translates to:
  /// **'{amount} kcal over the target'**
  String kcalOver(String amount);

  /// No description provided for @macroProgress.
  ///
  /// In en, this message translates to:
  /// **'{consumed} / {target} g'**
  String macroProgress(String consumed, String target);

  /// No description provided for @macroConsumed.
  ///
  /// In en, this message translates to:
  /// **'{consumed} g'**
  String macroConsumed(String consumed);

  /// No description provided for @emptyDayTitle.
  ///
  /// In en, this message translates to:
  /// **'No meals yet'**
  String get emptyDayTitle;

  /// No description provided for @emptyDayBody.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your meal or add it manually.'**
  String get emptyDayBody;

  /// No description provided for @addMeal.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addMeal;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;

  /// No description provided for @addManually.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addManually;

  /// No description provided for @previousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get previousDay;

  /// No description provided for @nextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get nextDay;

  /// No description provided for @openCalendar.
  ///
  /// In en, this message translates to:
  /// **'Open calendar'**
  String get openCalendar;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyHint.
  ///
  /// In en, this message translates to:
  /// **'Days with meals are marked. Tap a day to open it.'**
  String get historyHint;

  /// No description provided for @mealPhoto.
  ///
  /// In en, this message translates to:
  /// **'Meal photo'**
  String get mealPhoto;

  /// No description provided for @captureTitle.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get captureTitle;

  /// No description provided for @cameraPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed'**
  String get cameraPermissionTitle;

  /// No description provided for @cameraPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'CalSnap needs the camera to photograph your meal. You can still choose a photo from the gallery or add the meal manually.'**
  String get cameraPermissionBody;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available. You can choose a photo from the gallery instead.'**
  String get cameraUnavailable;

  /// No description provided for @flashOff.
  ///
  /// In en, this message translates to:
  /// **'Flash off'**
  String get flashOff;

  /// No description provided for @flashAuto.
  ///
  /// In en, this message translates to:
  /// **'Flash auto'**
  String get flashAuto;

  /// No description provided for @flashOn.
  ///
  /// In en, this message translates to:
  /// **'Flash on'**
  String get flashOn;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get switchCamera;

  /// No description provided for @shutter.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get shutter;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @retake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get retake;

  /// No description provided for @analyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get analyze;

  /// No description provided for @previewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the photo'**
  String get previewTitle;

  /// No description provided for @imageUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This image cannot be read. Try another photo.'**
  String get imageUnreadable;

  /// No description provided for @imageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This photo is too large to upload. Try another photo.'**
  String get imageTooLarge;

  /// No description provided for @analyzingTitle.
  ///
  /// In en, this message translates to:
  /// **'Analyzing your meal…'**
  String get analyzingTitle;

  /// No description provided for @stepPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing the photo'**
  String get stepPreparing;

  /// No description provided for @stepIdentifying.
  ///
  /// In en, this message translates to:
  /// **'Identifying foods'**
  String get stepIdentifying;

  /// No description provided for @stepPortions.
  ///
  /// In en, this message translates to:
  /// **'Estimating portions'**
  String get stepPortions;

  /// No description provided for @stepNutrition.
  ///
  /// In en, this message translates to:
  /// **'Calculating nutrition'**
  String get stepNutrition;

  /// No description provided for @errOffline.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. The diary is available offline. Analyzing a new photo requires a network.'**
  String get errOffline;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The analysis is taking too long. Please try again.'**
  String get errTimeout;

  /// No description provided for @errRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again in a little while.'**
  String get errRateLimited;

  /// No description provided for @errUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The analysis service is temporarily unavailable. Please try again.'**
  String get errUnavailable;

  /// No description provided for @errNotRecognized.
  ///
  /// In en, this message translates to:
  /// **'Could not confidently recognize the dish.'**
  String get errNotRecognized;

  /// No description provided for @errBadImage.
  ///
  /// In en, this message translates to:
  /// **'This photo cannot be analyzed. Try another photo.'**
  String get errBadImage;

  /// No description provided for @errUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errUnknown;

  /// No description provided for @tryAnotherPhoto.
  ///
  /// In en, this message translates to:
  /// **'Try another photo'**
  String get tryAnotherPhoto;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Recognized'**
  String get resultTitle;

  /// No description provided for @editMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit meal'**
  String get editMealTitle;

  /// No description provided for @newMealTitle.
  ///
  /// In en, this message translates to:
  /// **'New meal'**
  String get newMealTitle;

  /// No description provided for @estimateNotice.
  ///
  /// In en, this message translates to:
  /// **'Weights are estimates. Please check them before saving.'**
  String get estimateNotice;

  /// No description provided for @improveAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Improve accuracy'**
  String get improveAccuracy;

  /// No description provided for @improveAccuracyHint.
  ///
  /// In en, this message translates to:
  /// **'A second photo from the side helps with rice, pasta, potatoes, salads, cakes and meat.'**
  String get improveAccuracyHint;

  /// No description provided for @twoPhotoNote.
  ///
  /// In en, this message translates to:
  /// **'Estimated from two photos.'**
  String get twoPhotoNote;

  /// No description provided for @sideCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Side photo'**
  String get sideCaptureTitle;

  /// No description provided for @sideCaptureHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the camera at plate level and photograph the meal from the side.'**
  String get sideCaptureHint;

  /// No description provided for @replaceEditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace your changes?'**
  String get replaceEditsTitle;

  /// No description provided for @replaceEditsBody.
  ///
  /// In en, this message translates to:
  /// **'The new estimate replaces the items and weights you have edited. Your first result stays if you cancel.'**
  String get replaceEditsBody;

  /// No description provided for @replaceEditsAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get replaceEditsAction;

  /// No description provided for @keepFirstResult.
  ///
  /// In en, this message translates to:
  /// **'Keep the first result'**
  String get keepFirstResult;

  /// No description provided for @approxKcal.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String approxKcal(String value);

  /// No description provided for @totalKcal.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String totalKcal(String value);

  /// No description provided for @estimatedWeight.
  ///
  /// In en, this message translates to:
  /// **'estimate'**
  String get estimatedWeight;

  /// No description provided for @personalizedWeight.
  ///
  /// In en, this message translates to:
  /// **'adjusted'**
  String get personalizedWeight;

  /// No description provided for @personalizedWeightNote.
  ///
  /// In en, this message translates to:
  /// **'AI estimated {weight} g. Adjusted to your usual portions.'**
  String personalizedWeightNote(String weight);

  /// No description provided for @pleaseCheck.
  ///
  /// In en, this message translates to:
  /// **'Please check'**
  String get pleaseCheck;

  /// No description provided for @partialBanner.
  ///
  /// In en, this message translates to:
  /// **'Some ingredients may have been missed. Check the result before saving.'**
  String get partialBanner;

  /// No description provided for @estimatedNutritionNote.
  ///
  /// In en, this message translates to:
  /// **'Nutrition values for this item are estimated.'**
  String get estimatedNutritionNote;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @mealTypeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Meal type'**
  String get mealTypeFieldLabel;

  /// No description provided for @noItemsHint.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item to save.'**
  String get noItemsHint;

  /// No description provided for @removeItem.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeItem;

  /// No description provided for @editItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get editItemTitle;

  /// No description provided for @itemNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get itemNameLabel;

  /// No description provided for @itemWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get itemWeightLabel;

  /// No description provided for @per100Title.
  ///
  /// In en, this message translates to:
  /// **'Per 100 g'**
  String get per100Title;

  /// No description provided for @kcalPer100Label.
  ///
  /// In en, this message translates to:
  /// **'kcal per 100 g'**
  String get kcalPer100Label;

  /// No description provided for @errWeightRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a weight above 0 and up to 5000 g.'**
  String get errWeightRange;

  /// No description provided for @errNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name (up to 100 characters).'**
  String get errNameRequired;

  /// No description provided for @errKcal900.
  ///
  /// In en, this message translates to:
  /// **'Calories must be between 0 and 900 per 100 g.'**
  String get errKcal900;

  /// No description provided for @errMacro100.
  ///
  /// In en, this message translates to:
  /// **'Each value must be between 0 and 100 g.'**
  String get errMacro100;

  /// No description provided for @weightInGrams.
  ///
  /// In en, this message translates to:
  /// **'= {grams} g'**
  String weightInGrams(String grams);

  /// No description provided for @replaceProduct.
  ///
  /// In en, this message translates to:
  /// **'Replace product'**
  String get replaceProduct;

  /// No description provided for @discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardTitle;

  /// No description provided for @discardBody.
  ///
  /// In en, this message translates to:
  /// **'Your changes have not been saved.'**
  String get discardBody;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @deleteMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this meal?'**
  String get deleteMealTitle;

  /// No description provided for @deleteMealBody.
  ///
  /// In en, this message translates to:
  /// **'The meal and its photo will be removed.'**
  String get deleteMealBody;

  /// No description provided for @mealDeleted.
  ///
  /// In en, this message translates to:
  /// **'Meal deleted'**
  String get mealDeleted;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @emptyMealTitle.
  ///
  /// In en, this message translates to:
  /// **'The meal has no items'**
  String get emptyMealTitle;

  /// No description provided for @emptyMealBody.
  ///
  /// In en, this message translates to:
  /// **'A meal needs at least one item. You can delete the meal instead.'**
  String get emptyMealBody;

  /// No description provided for @deleteMeal.
  ///
  /// In en, this message translates to:
  /// **'Delete meal'**
  String get deleteMeal;

  /// No description provided for @mealSaved.
  ///
  /// In en, this message translates to:
  /// **'Meal saved'**
  String get mealSaved;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'The meal could not be saved. Your entries are kept, please try again.'**
  String get saveFailed;

  /// No description provided for @searchFoodsTitle.
  ///
  /// In en, this message translates to:
  /// **'Add food'**
  String get searchFoodsTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search foods'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No foods found.'**
  String get noResults;

  /// No description provided for @createCustomProduct.
  ///
  /// In en, this message translates to:
  /// **'Create custom product'**
  String get createCustomProduct;

  /// No description provided for @customProductTitle.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get customProductTitle;

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get statsTitle;

  /// No description provided for @statsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get statsToday;

  /// No description provided for @statsAverage.
  ///
  /// In en, this message translates to:
  /// **'Average per logged day'**
  String get statsAverage;

  /// No description provided for @statsAdherence.
  ///
  /// In en, this message translates to:
  /// **'{onTarget} of {logged, plural, one{{logged} logged day} other{{logged} logged days}} on target'**
  String statsAdherence(int onTarget, int logged);

  /// No description provided for @statsNoData.
  ///
  /// In en, this message translates to:
  /// **'No meals logged in the last 7 days.'**
  String get statsNoData;

  /// No description provided for @statsTarget.
  ///
  /// In en, this message translates to:
  /// **'Target {value} kcal'**
  String statsTarget(String value);

  /// No description provided for @statsChartLabel.
  ///
  /// In en, this message translates to:
  /// **'Calories per day for the last 7 days'**
  String get statsChartLabel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTargetsSection.
  ///
  /// In en, this message translates to:
  /// **'Daily targets'**
  String get settingsTargetsSection;

  /// No description provided for @settingsCalories.
  ///
  /// In en, this message translates to:
  /// **'Calorie target'**
  String get settingsCalories;

  /// No description provided for @settingsPlate.
  ///
  /// In en, this message translates to:
  /// **'My usual plate'**
  String get settingsPlate;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanBarcode;

  /// No description provided for @scanLabelButton.
  ///
  /// In en, this message translates to:
  /// **'Scan nutrition label'**
  String get scanLabelButton;

  /// No description provided for @scanSourceUser.
  ///
  /// In en, this message translates to:
  /// **'Saved by you'**
  String get scanSourceUser;

  /// No description provided for @labelScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition label'**
  String get labelScanTitle;

  /// No description provided for @labelHint.
  ///
  /// In en, this message translates to:
  /// **'Fill the frame with the nutrition table. Keep it straight, sharp and well lit.'**
  String get labelHint;

  /// No description provided for @labelRead.
  ///
  /// In en, this message translates to:
  /// **'Read label'**
  String get labelRead;

  /// No description provided for @labelNotRecognized.
  ///
  /// In en, this message translates to:
  /// **'No nutrition table was found in this photo. Photograph the table straight on and in focus, or enter the values yourself.'**
  String get labelNotRecognized;

  /// No description provided for @labelFillButton.
  ///
  /// In en, this message translates to:
  /// **'Fill from a label photo'**
  String get labelFillButton;

  /// No description provided for @labelCheckValues.
  ///
  /// In en, this message translates to:
  /// **'Check every value against the package before saving.'**
  String get labelCheckValues;

  /// No description provided for @labelConverted.
  ///
  /// In en, this message translates to:
  /// **'The label was per serving; the values were converted to 100 g.'**
  String get labelConverted;

  /// No description provided for @labelVolume.
  ///
  /// In en, this message translates to:
  /// **'The label was per 100 ml; the values are used as per 100 g.'**
  String get labelVolume;

  /// No description provided for @labelEnergyMismatch.
  ///
  /// In en, this message translates to:
  /// **'The energy does not match the protein, fat and carbohydrates. Please check the numbers.'**
  String get labelEnergyMismatch;

  /// No description provided for @labelEnergyEstimated.
  ///
  /// In en, this message translates to:
  /// **'The label showed no energy; it was calculated from protein, fat and carbohydrates.'**
  String get labelEnergyEstimated;

  /// No description provided for @labelLowConfidence.
  ///
  /// In en, this message translates to:
  /// **'The text was hard to read. Some numbers may be wrong.'**
  String get labelLowConfidence;

  /// No description provided for @labelIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some values could not be read. Please fill them in.'**
  String get labelIncomplete;

  /// No description provided for @customBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode {value}'**
  String customBarcode(String value);

  /// No description provided for @customServingLabel.
  ///
  /// In en, this message translates to:
  /// **'Serving, g (optional)'**
  String get customServingLabel;

  /// No description provided for @errServing.
  ///
  /// In en, this message translates to:
  /// **'Enter a serving from 1 to 2000 g or leave the field empty.'**
  String get errServing;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanTitle;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the barcode on the package'**
  String get scanHint;

  /// No description provided for @scanTorch.
  ///
  /// In en, this message translates to:
  /// **'Flashlight'**
  String get scanTorch;

  /// No description provided for @scanCameraError.
  ///
  /// In en, this message translates to:
  /// **'The camera cannot be used. You can type the barcode number below.'**
  String get scanCameraError;

  /// No description provided for @scanPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan barcodes. You can also type the number below.'**
  String get scanPermissionBody;

  /// No description provided for @scanManualLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode number'**
  String get scanManualLabel;

  /// No description provided for @scanManualInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid barcode: 8, 12, 13 or 14 digits.'**
  String get scanManualInvalid;

  /// No description provided for @scanFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get scanFind;

  /// No description provided for @scanLooking.
  ///
  /// In en, this message translates to:
  /// **'Looking up the product…'**
  String get scanLooking;

  /// No description provided for @scanNotFound.
  ///
  /// In en, this message translates to:
  /// **'No nutrition data was found for this product. You can add it as a custom product in the food search.'**
  String get scanNotFound;

  /// No description provided for @scanAnother.
  ///
  /// In en, this message translates to:
  /// **'Scan another'**
  String get scanAnother;

  /// No description provided for @scanSource.
  ///
  /// In en, this message translates to:
  /// **'Nutrition data: Open Food Facts (ODbL)'**
  String get scanSource;

  /// No description provided for @scanServing.
  ///
  /// In en, this message translates to:
  /// **'Serving: {value} g'**
  String scanServing(String value);

  /// No description provided for @plateGuideHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the camera directly above the plate'**
  String get plateGuideHint;

  /// No description provided for @qualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Retake for a better estimate?'**
  String get qualityTitle;

  /// No description provided for @issueSteepAngle.
  ///
  /// In en, this message translates to:
  /// **'The plate is shot at a steep angle. For a more accurate portion estimate, take the photo from above.'**
  String get issueSteepAngle;

  /// No description provided for @issuePlateCutOff.
  ///
  /// In en, this message translates to:
  /// **'The plate does not fit in the frame. Step back a little so the whole plate is visible.'**
  String get issuePlateCutOff;

  /// No description provided for @issueBlurry.
  ///
  /// In en, this message translates to:
  /// **'The photo looks blurry. Hold the phone steady and let it focus.'**
  String get issueBlurry;

  /// No description provided for @issueTooDark.
  ///
  /// In en, this message translates to:
  /// **'The photo is too dark. Move to better light or turn on the flash.'**
  String get issueTooDark;

  /// No description provided for @issueTooBright.
  ///
  /// In en, this message translates to:
  /// **'The photo is overexposed. Avoid glare and direct light.'**
  String get issueTooBright;

  /// No description provided for @plateChipUsual.
  ///
  /// In en, this message translates to:
  /// **'My usual plate: {value} cm'**
  String plateChipUsual(String value);

  /// No description provided for @plateChipOnce.
  ///
  /// In en, this message translates to:
  /// **'Plate for this photo: {value} cm'**
  String plateChipOnce(String value);

  /// No description provided for @plateChipAdd.
  ///
  /// In en, this message translates to:
  /// **'Add plate size'**
  String get plateChipAdd;

  /// No description provided for @plateSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Plate size'**
  String get plateSheetTitle;

  /// No description provided for @plateSheetBody.
  ///
  /// In en, this message translates to:
  /// **'A known plate size helps to estimate the portion. Typical dinner plates are 24 to 28 cm.'**
  String get plateSheetBody;

  /// No description provided for @plateOtherLabel.
  ///
  /// In en, this message translates to:
  /// **'Other, cm'**
  String get plateOtherLabel;

  /// No description provided for @plateRemember.
  ///
  /// In en, this message translates to:
  /// **'Remember as my usual plate'**
  String get plateRemember;

  /// No description provided for @plateNone.
  ///
  /// In en, this message translates to:
  /// **'No plate size'**
  String get plateNone;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @settingsPhotosSection.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get settingsPhotosSection;

  /// No description provided for @settingsSavePhotos.
  ///
  /// In en, this message translates to:
  /// **'Save meal photos'**
  String get settingsSavePhotos;

  /// No description provided for @settingsSavePhotosHint.
  ///
  /// In en, this message translates to:
  /// **'When off, photos are deleted after the analysis. Existing photos are kept.'**
  String get settingsSavePhotosHint;

  /// No description provided for @settingsPersonalizePortions.
  ///
  /// In en, this message translates to:
  /// **'Adapt weights to my corrections'**
  String get settingsPersonalizePortions;

  /// No description provided for @settingsPersonalizePortionsHint.
  ///
  /// In en, this message translates to:
  /// **'Learns from the weights you change and adjusts later estimates. Everything stays on this device.'**
  String get settingsPersonalizePortionsHint;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @settingsDataSection.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get settingsDataSection;

  /// No description provided for @settingsExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get settingsExportCsv;

  /// No description provided for @settingsExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get settingsExportJson;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'The export failed. Please try again.'**
  String get exportFailed;

  /// No description provided for @exportSubject.
  ///
  /// In en, this message translates to:
  /// **'CalSnap export'**
  String get exportSubject;

  /// No description provided for @settingsClearData.
  ///
  /// In en, this message translates to:
  /// **'Clear all data'**
  String get settingsClearData;

  /// No description provided for @clearDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all data?'**
  String get clearDataTitle;

  /// No description provided for @clearDataBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes all meals, photos, custom products and settings from this device. It cannot be undone. Consider exporting your data first.'**
  String get clearDataBody;

  /// No description provided for @clearDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get clearDataConfirm;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @valueUnitKcal.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String valueUnitKcal(String value);

  /// No description provided for @valueUnitGrams.
  ///
  /// In en, this message translates to:
  /// **'{value} g'**
  String valueUnitGrams(String value);

  /// No description provided for @valueUnitCm.
  ///
  /// In en, this message translates to:
  /// **'{value} cm'**
  String valueUnitCm(String value);

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyTitle;

  /// No description provided for @privacyDiary.
  ///
  /// In en, this message translates to:
  /// **'Your diary is stored only on this device.'**
  String get privacyDiary;

  /// No description provided for @privacyAnalysis.
  ///
  /// In en, this message translates to:
  /// **'When you analyze a photo, CalSnap sends the prepared photo (without metadata; two photos if you add a side photo, or a photo of a nutrition label if you scan one), the app language and, if set, your plate diameter to the CalSnap server, which forwards them to an AI provider.'**
  String get privacyAnalysis;

  /// No description provided for @privacyBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcodes are read on your device. To find a product, CalSnap sends only the barcode number to its server, which asks Open Food Facts. The scanner library may send anonymous technical statistics to Google.'**
  String get privacyBarcode;

  /// No description provided for @privacyNoStorage.
  ///
  /// In en, this message translates to:
  /// **'The CalSnap server does not store your photos after the request is finished.'**
  String get privacyNoStorage;

  /// No description provided for @privacyProvider.
  ///
  /// In en, this message translates to:
  /// **'The retention and training terms of the AI provider apply to what it receives.'**
  String get privacyProvider;

  /// No description provided for @privacyPolicyLink.
  ///
  /// In en, this message translates to:
  /// **'Full privacy policy'**
  String get privacyPolicyLink;

  /// No description provided for @privacyPolicyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The link could not be opened.'**
  String get privacyPolicyUnavailable;

  /// No description provided for @settingsServerSection.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get settingsServerSection;

  /// No description provided for @settingsServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get settingsServerUrl;

  /// No description provided for @serverUrlHelp.
  ///
  /// In en, this message translates to:
  /// **'Address of your CalSnap server, for example https://calsnap.example.com. Leave empty to use the default.'**
  String get serverUrlHelp;

  /// No description provided for @errServerUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a full address that starts with https://, without a login, query or #fragment.'**
  String get errServerUrlInvalid;

  /// No description provided for @errServerUrlInsecure.
  ///
  /// In en, this message translates to:
  /// **'Only secure https:// addresses are allowed.'**
  String get errServerUrlInsecure;

  /// No description provided for @errServerNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'The server address is not set. Enter the address of your CalSnap server in the settings to analyze photos.'**
  String get errServerNotConfigured;

  /// No description provided for @serverSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Server settings'**
  String get serverSettingsAction;

  /// No description provided for @errCertificate.
  ///
  /// In en, this message translates to:
  /// **'The server\'s security certificate is not trusted or has changed. Open the server settings and review it.'**
  String get errCertificate;

  /// No description provided for @serverCheckingCertificate.
  ///
  /// In en, this message translates to:
  /// **'Checking the server…'**
  String get serverCheckingCertificate;

  /// No description provided for @serverCertificateTrusted.
  ///
  /// In en, this message translates to:
  /// **'Self-signed certificate confirmed'**
  String get serverCertificateTrusted;

  /// No description provided for @certTrustTitle.
  ///
  /// In en, this message translates to:
  /// **'Trust this server?'**
  String get certTrustTitle;

  /// No description provided for @certChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Server certificate changed'**
  String get certChangedTitle;

  /// No description provided for @certTrustBody.
  ///
  /// In en, this message translates to:
  /// **'The server {host} uses a certificate that this device does not recognize, most likely a self-signed one. Compare the fingerprint below with the one in the server log. Trust the server only if they are identical.'**
  String certTrustBody(String host);

  /// No description provided for @certChangedBody.
  ///
  /// In en, this message translates to:
  /// **'The certificate of {host} is not the one you confirmed earlier. That is expected if the server generated a new certificate. Otherwise someone may be intercepting the connection. Compare the fingerprint with the server log before trusting it.'**
  String certChangedBody(String host);

  /// No description provided for @certFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint'**
  String get certFingerprintLabel;

  /// No description provided for @certSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get certSubjectLabel;

  /// No description provided for @certValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String certValidUntil(String date);

  /// No description provided for @certTrustAction.
  ///
  /// In en, this message translates to:
  /// **'Trust'**
  String get certTrustAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
