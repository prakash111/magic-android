import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api.dart';

String appTr(
  String key, [
  Map<String, Object?> parameters = const {},
  num? count,
]) => AppLocalizations.current.translate(key, parameters, count);

class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final bool isRtl;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    this.isRtl = false,
  });

  factory AppLanguage.fromJson(Map data) => AppLanguage(
    code: data['code'] as String,
    name: data['name'] as String? ?? data['code'] as String,
    nativeName:
        data['native'] as String? ??
        data['name'] as String? ??
        data['code'] as String,
    isRtl: data['direction'] == 'rtl',
  );

  Locale get locale {
    final parts = code.replaceAll('-', '_').split('_');
    return Locale.fromSubtags(
      languageCode: parts.first,
      scriptCode: parts.length > 1 && parts[1].length == 4 ? parts[1] : null,
      countryCode: parts.length > 1 && parts.last.length != 4
          ? parts.last
          : null,
    );
  }
}

class AppLocalizations extends ChangeNotifier {
  static AppLocalizations current = AppLocalizations();
  final MobileApi api;
  final Future<SharedPreferences> Function() preferences;
  final Future<Map<String, dynamic>> Function(String? locale)? loadCatalog;
  List<AppLanguage> languages = const [];
  String localeCode = 'en';
  String defaultLocale = 'en';
  String? error;
  bool refreshing = false;
  int revision = 0;
  String? _selected;
  String? _serverRevision;
  Map<String, String> _messages = {};
  Map<String, String> _fallback = {};
  Map<String, String> _normalized = {};
  final Map<String, String> _sourceKeys = {};
  List<_TranslationPattern> _patterns = [];
  SharedPreferences? _prefs;
  Future<void>? _initialization;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  AppLocalizations({
    MobileApi? api,
    Future<SharedPreferences> Function()? preferences,
    this.loadCatalog,
  }) : api = api ?? MobileApi.instance,
       preferences = preferences ?? SharedPreferences.getInstance {
    initializeDateFormatting();
  }

  static AppLocalizations watch(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? current;

  String get _prefix => 'magicai.localization.${api.origin}';
  AppLanguage get language => languages.firstWhere(
    (language) => language.code == localeCode,
    orElse: () =>
        AppLanguage(code: localeCode, name: localeCode, nativeName: localeCode),
  );
  Locale get locale => language.locale;
  TextDirection get direction =>
      language.isRtl ? TextDirection.rtl : TextDirection.ltr;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      _prefs = await preferences().timeout(const Duration(seconds: 3));
      if (_disposed) return;
      _selected = _prefs!.getString('$_prefix.selected');
      final cached = _prefs!.getString('$_prefix.catalog');
      if (cached != null) {
        final body = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        final cachedLocale = _selected ?? body['default_locale'];
        final saved = _prefs!.getString('$_prefix.bundle.$cachedLocale');
        _apply(
          saved == null
              ? body
              : Map<String, dynamic>.from(jsonDecode(saved) as Map),
        );
      }
    } catch (_) {
      // Preferences and a corrupt cache must never prevent startup.
    }
    if (_disposed) return;
    await refresh();
    if (!_disposed) {
      _timer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> select(String code) async {
    if (!languages.any((language) => language.code == code)) return;
    await refresh(selected: code);
  }

  Future<void> refresh({String? selected}) async {
    if (_disposed || (refreshing && selected == null)) return;
    final generation = ++_generation;
    final requested = selected ?? _selected;
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      if (selected != null && selected != localeCode) {
        final cached = _prefs?.getString('$_prefix.bundle.$selected');
        if (cached != null) {
          final data = Map<String, dynamic>.from(jsonDecode(cached) as Map);
          _setMessages(data);
          localeCode = selected;
          _selected = selected;
          MobileApi.languageCode = localeCode;
          revision++;
          notifyListeners();
        }
      }
      final body = await (loadCatalog?.call(requested) ?? _load(requested));
      if (_disposed || generation != _generation) return;
      final supported = (body['languages'] as List)
          .whereType<Map>()
          .map((item) => item['code'])
          .toSet();
      if (requested != null && !supported.contains(requested)) {
        _selected = null;
        await _prefs?.remove('$_prefix.selected');
      } else if (selected != null) {
        _selected = selected;
      }
      _apply(body);
      try {
        _prefs ??= await preferences().timeout(const Duration(seconds: 3));
        if (_selected != null) {
          await _prefs!.setString('$_prefix.selected', _selected!);
        }
        await _prefs!.setString('$_prefix.catalog', jsonEncode(body));
        await _prefs!.setString(
          '$_prefix.bundle.$localeCode',
          jsonEncode(body),
        );
      } catch (_) {}
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Unable to refresh languages. Your saved translations are still available.';
        if (_selected != null) {
          try {
            await _prefs?.setString('$_prefix.selected', _selected!);
          } catch (_) {}
        }
      }
    } finally {
      if (!_disposed && generation == _generation) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> _load(String? code) async {
    final path =
        '/translations${code == null ? '' : '?locale=${Uri.encodeQueryComponent(code)}'}';
    final body = await api.request(
      path,
      authenticated: false,
      notifyAuthFailure: false,
      notifyLicenseFailure: false,
    );
    if (body is! Map) {
      throw const FormatException('Invalid translation catalog');
    }
    return Map<String, dynamic>.from(body);
  }

  void _apply(Map<String, dynamic> body) {
    if (_disposed) return;
    if (body['schema_version'] != 1 ||
        body['languages'] is! List ||
        body['translations'] is! Map ||
        body['fallback'] is! Map) {
      throw const FormatException('Invalid translation catalog');
    }
    final next = (body['languages'] as List)
        .whereType<Map>()
        .map(AppLanguage.fromJson)
        .toList();
    final code = body['locale'];
    if (code is! String || !next.any((language) => language.code == code)) {
      throw const FormatException('Unsupported language');
    }
    languages = next;
    defaultLocale = body['default_locale'] as String;
    localeCode = code;
    MobileApi.languageCode = code;
    _setMessages(body);
    if (_serverRevision != body['revision']) {
      _serverRevision = body['revision'] as String?;
      revision++;
    }
    Intl.defaultLocale = Intl.verifiedLocale(
      code.replaceAll('-', '_'),
      DateFormat.localeExists,
      onFailure: (_) => 'en',
    );
    if (!_disposed) notifyListeners();
  }

  void _setMessages(Map body) {
    Map<String, String> strings(dynamic value) => value is Map
        ? Map.fromEntries(
            value.entries
                .where(
                  (entry) =>
                      entry.key is String &&
                      entry.value is String &&
                      (entry.value as String).isNotEmpty,
                )
                .map(
                  (entry) =>
                      MapEntry(entry.key as String, entry.value as String),
                ),
          )
        : {};
    _messages = strings(body['translations']);
    _fallback = strings(body['fallback']);
    for (final entry in _messages.entries) {
      if (entry.key != entry.value) {
        _sourceKeys.putIfAbsent(entry.value, () => entry.key);
      }
    }
    _patterns = [
      for (final entry in [..._fallback.entries, ..._messages.entries])
        if (entry.value.contains(RegExp(r':[A-Za-z]')) &&
            !entry.value.contains('|') &&
            entry.value
                    .replaceAll(RegExp(r':[A-Za-z][A-Za-z0-9_]*'), '')
                    .trim()
                    .length >=
                3)
          _TranslationPattern(entry.key, entry.value),
    ];
    _normalized = {
      for (final entry in _fallback.entries) _normalize(entry.key): entry.value,
    };
    for (final entry in _messages.entries) {
      _normalized[_normalize(entry.key)] = entry.value;
    }
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[.!?:]+$'), '');

  String translate(
    String key, [
    Map<String, Object?> parameters = const {},
    num? count,
  ]) {
    if (!_messages.containsKey(key) && !_fallback.containsKey(key)) {
      key = _sourceKeys[key] ?? key;
    }
    final replacements = <String, Object?>{...parameters};
    String? matched =
        _messages[key] ?? _normalized[_normalize(key)] ?? _fallback[key];
    if (matched == null && key.length < 5000) {
      for (final pattern in _patterns) {
        final match = pattern.expression.firstMatch(key);
        if (match == null) continue;
        matched = _messages[pattern.key] ?? _fallback[pattern.key];
        for (var index = 0; index < pattern.names.length; index++) {
          replacements.putIfAbsent(
            pattern.names[index],
            () => match.group(index + 1),
          );
        }
        break;
      }
    }
    var result = matched ?? key;
    if (count != null && result.contains('|')) {
      final forms = result.split('|');
      String? chosen;
      for (final form in forms) {
        final exact = RegExp(
          r'^\{(-?\d+)\}\s*(.*)$',
          dotAll: true,
        ).firstMatch(form);
        if (exact != null && num.parse(exact[1]!) == count) {
          chosen = exact[2];
          break;
        }
        final range = RegExp(
          r'^\[(-?\d+|\*),\s*(-?\d+|\*)\]\s*(.*)$',
          dotAll: true,
        ).firstMatch(form);
        if (range != null &&
            (range[1] == '*' || count >= num.parse(range[1]!)) &&
            (range[2] == '*' || count <= num.parse(range[2]!))) {
          chosen = range[3];
          break;
        }
      }
      result =
          chosen ??
          forms[count == 1 ? 0 : forms.length - 1].replaceFirst(
            RegExp(r'^(?:\{[^}]+\}|\[[^]]+\])\s*'),
            '',
          );
    }
    final substitutions = <String, Object?>{...replacements};
    if (count != null) {
      substitutions['count'] = count;
    }
    for (final entry in substitutions.entries) {
      final value = entry.value?.toString() ?? '';
      result = result.replaceAll(
        ':${entry.key.toUpperCase()}',
        value.toUpperCase(),
      );
      if (entry.key.isNotEmpty) {
        final title = entry.key[0].toUpperCase() + entry.key.substring(1);
        result = result.replaceAll(
          ':$title',
          value.isEmpty ? value : value[0].toUpperCase() + value.substring(1),
        );
      }
      result = result.replaceAll(':${entry.key}', value);
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

class _TranslationPattern {
  final String key;
  final List<String> names = [];
  late final RegExp expression;
  _TranslationPattern(this.key, String source) {
    final pattern = StringBuffer('^');
    var end = 0;
    for (final match in RegExp(
      r':([A-Za-z][A-Za-z0-9_]*)',
    ).allMatches(source)) {
      pattern.write(RegExp.escape(source.substring(end, match.start)));
      pattern.write('(.+?)');
      names.add(match[1]!);
      end = match.end;
    }
    pattern.write(RegExp.escape(source.substring(end)));
    pattern.write(r'$');
    expression = RegExp(pattern.toString(), caseSensitive: false);
  }
}

class AppTranslationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  final AppLocalizations controller;
  final int revision;
  AppTranslationsDelegate(this.controller) : revision = controller.revision;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(controller);
  @override
  bool shouldReload(AppTranslationsDelegate old) =>
      old.controller != controller || old.revision != revision;
}
