import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'app_localizations.dart';

String get _locale => Intl.verifiedLocale(
  AppLocalizations.current.localeCode.replaceAll('-', '_'),
  DateFormat.localeExists,
  onFailure: (_) => 'en',
)!;

class ServerMaterialLocalizations extends DefaultMaterialLocalizations {
  const ServerMaterialLocalizations();
  @override
  String get dateSeparator => appTr(super.dateSeparator);
  @override
  String get dateHelpText => DateFormat.yMd(_locale).pattern!;
  @override
  String get selectYearSemanticsLabel => appTr(super.selectYearSemanticsLabel);
  @override
  String get unspecifiedDate => appTr(super.unspecifiedDate);
  @override
  String get unspecifiedDateRange => appTr(super.unspecifiedDateRange);
  @override
  String get dateInputLabel => appTr(super.dateInputLabel);
  @override
  String get dateRangeStartLabel => appTr(super.dateRangeStartLabel);
  @override
  String get dateRangeEndLabel => appTr(super.dateRangeEndLabel);
  @override
  String get invalidDateFormatLabel => appTr(super.invalidDateFormatLabel);
  @override
  String get invalidDateRangeLabel => appTr(super.invalidDateRangeLabel);
  @override
  String get dateOutOfRangeLabel => appTr(super.dateOutOfRangeLabel);
  @override
  String get saveButtonLabel => appTr(super.saveButtonLabel);
  @override
  String get datePickerHelpText => appTr(super.datePickerHelpText);
  @override
  String get dateRangePickerHelpText => appTr(super.dateRangePickerHelpText);
  @override
  String get calendarModeButtonLabel => appTr(super.calendarModeButtonLabel);
  @override
  String get inputDateModeButtonLabel => appTr(super.inputDateModeButtonLabel);
  @override
  String get timePickerDialHelpText => appTr(super.timePickerDialHelpText);
  @override
  String get timePickerInputHelpText => appTr(super.timePickerInputHelpText);
  @override
  String get timePickerHourLabel => appTr(super.timePickerHourLabel);
  @override
  String get timePickerMinuteLabel => appTr(super.timePickerMinuteLabel);
  @override
  String get invalidTimeLabel => appTr(super.invalidTimeLabel);
  @override
  String get dialModeButtonLabel => appTr(super.dialModeButtonLabel);
  @override
  String get inputTimeModeButtonLabel => appTr(super.inputTimeModeButtonLabel);
  @override
  String get openAppDrawerTooltip => appTr(super.openAppDrawerTooltip);
  @override
  String get backButtonTooltip => appTr(super.backButtonTooltip);
  @override
  String get clearButtonTooltip => appTr(super.clearButtonTooltip);
  @override
  String get closeButtonTooltip => appTr(super.closeButtonTooltip);
  @override
  String get deleteButtonTooltip => appTr(super.deleteButtonTooltip);
  @override
  String get moreButtonTooltip => appTr(super.moreButtonTooltip);
  @override
  String get nextMonthTooltip => appTr(super.nextMonthTooltip);
  @override
  String get previousMonthTooltip => appTr(super.previousMonthTooltip);
  @override
  String get nextPageTooltip => appTr(super.nextPageTooltip);
  @override
  String get previousPageTooltip => appTr(super.previousPageTooltip);
  @override
  String get firstPageTooltip => appTr(super.firstPageTooltip);
  @override
  String get lastPageTooltip => appTr(super.lastPageTooltip);
  @override
  String get showMenuTooltip => appTr(super.showMenuTooltip);
  @override
  String get drawerLabel => appTr(super.drawerLabel);
  @override
  String get menuBarMenuLabel => appTr(super.menuBarMenuLabel);
  @override
  String get popupMenuLabel => appTr(super.popupMenuLabel);
  @override
  String get dialogLabel => appTr(super.dialogLabel);
  @override
  String get alertDialogLabel => appTr(super.alertDialogLabel);
  @override
  String get searchFieldLabel => appTr(super.searchFieldLabel);
  @override
  String get currentDateLabel => appTr(super.currentDateLabel);
  @override
  String get selectedDateLabel => appTr(super.selectedDateLabel);
  @override
  String get scrimLabel => appTr(super.scrimLabel);
  @override
  String get bottomSheetLabel => appTr(super.bottomSheetLabel);
  @override
  String get licensesPageTitle => appTr(super.licensesPageTitle);
  @override
  String get rowsPerPageTitle => appTr(super.rowsPerPageTitle);
  @override
  String get cancelButtonLabel => appTr(super.cancelButtonLabel);
  @override
  String get closeButtonLabel => appTr(super.closeButtonLabel);
  @override
  String get continueButtonLabel => appTr(super.continueButtonLabel);
  @override
  String get copyButtonLabel => appTr(super.copyButtonLabel);
  @override
  String get cutButtonLabel => appTr(super.cutButtonLabel);
  @override
  String get scanTextButtonLabel => appTr(super.scanTextButtonLabel);
  @override
  String get okButtonLabel => appTr(super.okButtonLabel);
  @override
  String get pasteButtonLabel => appTr(super.pasteButtonLabel);
  @override
  String get selectAllButtonLabel => appTr(super.selectAllButtonLabel);
  @override
  String get lookUpButtonLabel => appTr(super.lookUpButtonLabel);
  @override
  String get searchWebButtonLabel => appTr(super.searchWebButtonLabel);
  @override
  String get shareButtonLabel => appTr(super.shareButtonLabel);
  @override
  String get viewLicensesButtonLabel => appTr(super.viewLicensesButtonLabel);
  @override
  String get anteMeridiemAbbreviation => appTr(super.anteMeridiemAbbreviation);
  @override
  String get postMeridiemAbbreviation => appTr(super.postMeridiemAbbreviation);
  @override
  String get timePickerHourModeAnnouncement =>
      appTr(super.timePickerHourModeAnnouncement);
  @override
  String get timePickerMinuteModeAnnouncement =>
      appTr(super.timePickerMinuteModeAnnouncement);
  @override
  String get modalBarrierDismissLabel => appTr(super.modalBarrierDismissLabel);
  @override
  String get menuDismissLabel => appTr(super.menuDismissLabel);
  @override
  String get signedInLabel => appTr(super.signedInLabel);
  @override
  String get hideAccountsLabel => appTr(super.hideAccountsLabel);
  @override
  String get showAccountsLabel => appTr(super.showAccountsLabel);
  @override
  String get reorderItemUp => appTr(super.reorderItemUp);
  @override
  String get reorderItemDown => appTr(super.reorderItemDown);
  @override
  String get reorderItemLeft => appTr(super.reorderItemLeft);
  @override
  String get reorderItemRight => appTr(super.reorderItemRight);
  @override
  String get reorderItemToEnd => appTr(super.reorderItemToEnd);
  @override
  String get reorderItemToStart => appTr(super.reorderItemToStart);
  @override
  String get expandedIconTapHint => appTr(super.expandedIconTapHint);
  @override
  String get collapsedIconTapHint => appTr(super.collapsedIconTapHint);
  @override
  String get expansionTileExpandedHint =>
      appTr(super.expansionTileExpandedHint);
  @override
  String get expansionTileCollapsedHint =>
      appTr(super.expansionTileCollapsedHint);
  @override
  String get expansionTileExpandedTapHint =>
      appTr(super.expansionTileExpandedTapHint);
  @override
  String get expansionTileCollapsedTapHint =>
      appTr(super.expansionTileCollapsedTapHint);
  @override
  String get expandedHint => appTr(super.expandedHint);
  @override
  String get collapsedHint => appTr(super.collapsedHint);
  @override
  String get refreshIndicatorSemanticLabel =>
      appTr(super.refreshIndicatorSemanticLabel);
  @override
  String get keyboardKeyAlt => appTr(super.keyboardKeyAlt);
  @override
  String get keyboardKeyAltGraph => appTr(super.keyboardKeyAltGraph);
  @override
  String get keyboardKeyBackspace => appTr(super.keyboardKeyBackspace);
  @override
  String get keyboardKeyCapsLock => appTr(super.keyboardKeyCapsLock);
  @override
  String get keyboardKeyChannelDown => appTr(super.keyboardKeyChannelDown);
  @override
  String get keyboardKeyChannelUp => appTr(super.keyboardKeyChannelUp);
  @override
  String get keyboardKeyControl => appTr(super.keyboardKeyControl);
  @override
  String get keyboardKeyDelete => appTr(super.keyboardKeyDelete);
  @override
  String get keyboardKeyEject => appTr(super.keyboardKeyEject);
  @override
  String get keyboardKeyEnd => appTr(super.keyboardKeyEnd);
  @override
  String get keyboardKeyEscape => appTr(super.keyboardKeyEscape);
  @override
  String get keyboardKeyFn => appTr(super.keyboardKeyFn);
  @override
  String get keyboardKeyHome => appTr(super.keyboardKeyHome);
  @override
  String get keyboardKeyInsert => appTr(super.keyboardKeyInsert);
  @override
  String get keyboardKeyMeta => appTr(super.keyboardKeyMeta);
  @override
  String get keyboardKeyMetaMacOs => appTr(super.keyboardKeyMetaMacOs);
  @override
  String get keyboardKeyMetaWindows => appTr(super.keyboardKeyMetaWindows);
  @override
  String get keyboardKeyNumLock => appTr(super.keyboardKeyNumLock);
  @override
  String get keyboardKeyNumpad1 => appTr(super.keyboardKeyNumpad1);
  @override
  String get keyboardKeyNumpad2 => appTr(super.keyboardKeyNumpad2);
  @override
  String get keyboardKeyNumpad3 => appTr(super.keyboardKeyNumpad3);
  @override
  String get keyboardKeyNumpad4 => appTr(super.keyboardKeyNumpad4);
  @override
  String get keyboardKeyNumpad5 => appTr(super.keyboardKeyNumpad5);
  @override
  String get keyboardKeyNumpad6 => appTr(super.keyboardKeyNumpad6);
  @override
  String get keyboardKeyNumpad7 => appTr(super.keyboardKeyNumpad7);
  @override
  String get keyboardKeyNumpad8 => appTr(super.keyboardKeyNumpad8);
  @override
  String get keyboardKeyNumpad9 => appTr(super.keyboardKeyNumpad9);
  @override
  String get keyboardKeyNumpad0 => appTr(super.keyboardKeyNumpad0);
  @override
  String get keyboardKeyNumpadAdd => appTr(super.keyboardKeyNumpadAdd);
  @override
  String get keyboardKeyNumpadComma => appTr(super.keyboardKeyNumpadComma);
  @override
  String get keyboardKeyNumpadDecimal => appTr(super.keyboardKeyNumpadDecimal);
  @override
  String get keyboardKeyNumpadDivide => appTr(super.keyboardKeyNumpadDivide);
  @override
  String get keyboardKeyNumpadEnter => appTr(super.keyboardKeyNumpadEnter);
  @override
  String get keyboardKeyNumpadEqual => appTr(super.keyboardKeyNumpadEqual);
  @override
  String get keyboardKeyNumpadMultiply =>
      appTr(super.keyboardKeyNumpadMultiply);
  @override
  String get keyboardKeyNumpadParenLeft =>
      appTr(super.keyboardKeyNumpadParenLeft);
  @override
  String get keyboardKeyNumpadParenRight =>
      appTr(super.keyboardKeyNumpadParenRight);
  @override
  String get keyboardKeyNumpadSubtract =>
      appTr(super.keyboardKeyNumpadSubtract);
  @override
  String get keyboardKeyPageDown => appTr(super.keyboardKeyPageDown);
  @override
  String get keyboardKeyPageUp => appTr(super.keyboardKeyPageUp);
  @override
  String get keyboardKeyPower => appTr(super.keyboardKeyPower);
  @override
  String get keyboardKeyPowerOff => appTr(super.keyboardKeyPowerOff);
  @override
  String get keyboardKeyPrintScreen => appTr(super.keyboardKeyPrintScreen);
  @override
  String get keyboardKeyScrollLock => appTr(super.keyboardKeyScrollLock);
  @override
  String get keyboardKeySelect => appTr(super.keyboardKeySelect);
  @override
  String get keyboardKeyShift => appTr(super.keyboardKeyShift);
  @override
  String get keyboardKeySpace => appTr(super.keyboardKeySpace);
  @override
  String formatDecimal(int number) =>
      NumberFormat.decimalPattern(_locale).format(number);
  @override
  String formatYear(DateTime date) => DateFormat.y(_locale).format(date);
  @override
  String formatFullDate(DateTime date) =>
      DateFormat.yMMMMEEEEd(_locale).format(date);
  @override
  String formatMediumDate(DateTime date) =>
      DateFormat.MMMEd(_locale).format(date);
  @override
  String formatMonthYear(DateTime date) =>
      DateFormat.yMMMM(_locale).format(date);
  @override
  String formatCompactDate(DateTime date) =>
      DateFormat.yMd(_locale).format(date);
  @override
  String formatShortDate(DateTime date) =>
      DateFormat.yMMMd(_locale).format(date);
  @override
  String formatShortMonthDay(DateTime date) =>
      DateFormat.MMMd(_locale).format(date);
  @override
  DateTime? parseCompactDate(String? inputString) {
    if (inputString == null) return null;
    try {
      return DateFormat.yMd(_locale).parseStrict(inputString);
    } catch (_) {
      return null;
    }
  }

  @override
  List<String> get narrowWeekdays =>
      DateFormat.EEEE(_locale).dateSymbols.NARROWWEEKDAYS;
  @override
  int get firstDayOfWeekIndex =>
      (DateFormat.EEEE(_locale).dateSymbols.FIRSTDAYOFWEEK + 1) % 7;
  @override
  String formatTimeOfDay(
    TimeOfDay timeOfDay, {
    bool alwaysUse24HourFormat = false,
  }) {
    final date = DateTime(2000, 1, 1, timeOfDay.hour, timeOfDay.minute);
    return (alwaysUse24HourFormat
            ? DateFormat.Hm(_locale)
            : DateFormat.jm(_locale))
        .format(date);
  }

  @override
  String aboutListTileTitle(String applicationName) =>
      appTr('About :name', {'name': applicationName});
  @override
  String tabLabel({required int tabIndex, required int tabCount}) =>
      appTr('Tab :index of :count', {'index': tabIndex, 'count': tabCount});
  @override
  String remainingTextFieldCharacterCount(int remaining) =>
      appTr(':count characters remaining', {}, remaining);
}

class ServerCupertinoLocalizations extends DefaultCupertinoLocalizations {
  const ServerCupertinoLocalizations();
  @override
  String get anteMeridiemAbbreviation => appTr(super.anteMeridiemAbbreviation);
  @override
  String get postMeridiemAbbreviation => appTr(super.postMeridiemAbbreviation);
  @override
  String get todayLabel => appTr(super.todayLabel);
  @override
  String get alertDialogLabel => appTr(super.alertDialogLabel);
  @override
  String get cutButtonLabel => appTr(super.cutButtonLabel);
  @override
  String get copyButtonLabel => appTr(super.copyButtonLabel);
  @override
  String get pasteButtonLabel => appTr(super.pasteButtonLabel);
  @override
  String get clearButtonLabel => appTr(super.clearButtonLabel);
  @override
  String get noSpellCheckReplacementsLabel =>
      appTr(super.noSpellCheckReplacementsLabel);
  @override
  String get selectAllButtonLabel => appTr(super.selectAllButtonLabel);
  @override
  String get lookUpButtonLabel => appTr(super.lookUpButtonLabel);
  @override
  String get searchWebButtonLabel => appTr(super.searchWebButtonLabel);
  @override
  String get shareButtonLabel => appTr(super.shareButtonLabel);
  @override
  String get searchTextFieldPlaceholderLabel =>
      appTr(super.searchTextFieldPlaceholderLabel);
  @override
  String get modalBarrierDismissLabel => appTr(super.modalBarrierDismissLabel);
  @override
  String get menuDismissLabel => appTr(super.menuDismissLabel);
  @override
  String get cancelButtonLabel => appTr(super.cancelButtonLabel);
  @override
  String get backButtonLabel => appTr(super.backButtonLabel);
  @override
  String get expansionTileExpandedHint =>
      appTr(super.expansionTileExpandedHint);
  @override
  String get expansionTileCollapsedHint =>
      appTr(super.expansionTileCollapsedHint);
  @override
  String get expansionTileExpandedTapHint =>
      appTr(super.expansionTileExpandedTapHint);
  @override
  String get expansionTileCollapsedTapHint =>
      appTr(super.expansionTileCollapsedTapHint);
  @override
  String get expandedHint => appTr(super.expandedHint);
  @override
  String get collapsedHint => appTr(super.collapsedHint);
  @override
  String datePickerMonth(int monthIndex) =>
      DateFormat.MMMM(_locale).format(DateTime(2000, monthIndex));
  @override
  String datePickerStandaloneMonth(int monthIndex) =>
      datePickerMonth(monthIndex);
  @override
  String datePickerMediumDate(DateTime date) =>
      DateFormat.MMMEd(_locale).format(date);
}

class ServerWidgetsLocalizations extends DefaultWidgetsLocalizations {
  @override
  String get reorderItemUp => appTr(super.reorderItemUp);
  @override
  String get reorderItemDown => appTr(super.reorderItemDown);
  @override
  String get reorderItemLeft => appTr(super.reorderItemLeft);
  @override
  String get reorderItemRight => appTr(super.reorderItemRight);
  @override
  String get reorderItemToEnd => appTr(super.reorderItemToEnd);
  @override
  String get reorderItemToStart => appTr(super.reorderItemToStart);
  @override
  String get searchResultsFound => appTr(super.searchResultsFound);
  @override
  String get noResultsFound => appTr(super.noResultsFound);
  @override
  String get copyButtonLabel => appTr(super.copyButtonLabel);
  @override
  String get cutButtonLabel => appTr(super.cutButtonLabel);
  @override
  String get pasteButtonLabel => appTr(super.pasteButtonLabel);
  @override
  String get selectAllButtonLabel => appTr(super.selectAllButtonLabel);
  @override
  String get lookUpButtonLabel => appTr(super.lookUpButtonLabel);
  @override
  String get searchWebButtonLabel => appTr(super.searchWebButtonLabel);
  @override
  String get shareButtonLabel => appTr(super.shareButtonLabel);
  @override
  String get radioButtonUnselectedLabel =>
      appTr(super.radioButtonUnselectedLabel);

  const ServerWidgetsLocalizations();
  @override
  TextDirection get textDirection => AppLocalizations.current.direction;
}

class ServerLocalizationsDelegate<T> extends LocalizationsDelegate<T> {
  final T Function() create;
  final int revision;
  const ServerLocalizationsDelegate(this.create, this.revision);
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<T> load(Locale locale) => SynchronousFuture(create());
  @override
  bool shouldReload(ServerLocalizationsDelegate<T> old) =>
      old.revision != revision;
}
