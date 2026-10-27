import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/app_localizations.dart';
import 'package:magicai_mobile/services/framework_localizations.dart';
import 'package:magicai_mobile/widgets/language_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;

Map<String, dynamic> catalog({
  String code = 'de',
  String defaultCode = 'de',
  List<String> codes = const ['en', 'de', 'ar'],
  Map<String, String> extra = const {},
}) {
  final messages = switch (code) {
    'de' => {
      'Save': 'Speichern',
      'Settings': 'Einstellungen',
      'Language': 'Sprache',
      'validation.required': 'Das Feld :attribute ist erforderlich.',
      'Cancel': 'Abbrechen',
      'Hello :name': 'Hallo :name',
      ':count file|:count files': ':count Datei|:count Dateien',
    },
    'ar' => {'Save': 'حفظ', 'Settings': 'الإعدادات'},
    _ => {'Save': 'Save', 'Settings': 'Settings'},
  };
  final body = <String, dynamic>{
    'schema_version': 1,
    'default_locale': defaultCode,
    'fallback_locale': 'en',
    'locale': code,
    'languages': [
      for (final language in codes)
        {
          'code': language,
          'name': language,
          'native': language == 'de' ? 'Deutsch' : language,
          'direction': language == 'ar' ? 'rtl' : 'ltr',
        },
    ],
    'translations': {...messages, ...extra},
    'fallback': {
      'Missing selected': 'English fallback',
      'validation.required': 'The :attribute field is required.',
    },
  };
  body['revision'] = jsonEncode(body);
  return body;
}

class TranslationHost extends StatelessWidget {
  final AppLocalizations translations;
  const TranslationHost(this.translations, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: translations,
    builder: (context, _) => MaterialApp(
      locale: translations.locale,
      supportedLocales: translations.languages.map(
        (language) => language.locale,
      ),
      localizationsDelegates: [
        AppTranslationsDelegate(translations),
        ServerLocalizationsDelegate<MaterialLocalizations>(
          () => const ServerMaterialLocalizations(),
          translations.revision,
        ),
        ServerLocalizationsDelegate<CupertinoLocalizations>(
          () => const ServerCupertinoLocalizations(),
          translations.revision,
        ),
        ServerLocalizationsDelegate<WidgetsLocalizations>(
          () => const ServerWidgetsLocalizations(),
          translations.revision,
        ),
      ],
      home: const TranslationPage(),
    ),
  );
}

class TranslationPage extends StatefulWidget {
  const TranslationPage({super.key});
  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  int taps = 0;
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(appTr('Settings')),
        actions: const [LanguagePicker()],
      ),
      body: Column(
        children: [
          Text('$taps'),
          FilledButton(
            onPressed: () => setState(() => taps++),
            child: Text(appTr('Save')),
          ),
          const Text('Save', key: ValueKey('user-content')),
          TextFormField(
            decoration: InputDecoration(labelText: appTr('Settings')),
          ),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations previous;
  final controllers = <AppLocalizations>[];
  AppLocalizations create(Future<Map<String, dynamic>> Function(String?) load) {
    final result = AppLocalizations(loadCatalog: load);
    controllers.add(result);
    AppLocalizations.current = result;
    return result;
  }

  setUp(() {
    previous = AppLocalizations.current;
    MobileApi.languageCode = null;
    MobileApi.failure.value = null;
    SharedPreferences.setMockInitialValues({});
  });

  test('background language failures preserve the app while normal license checks still fail closed', () async {
    final api = MobileApi(
      origin: Uri.parse('https://customer.example.test'),
      store: MemorySecureStore(),
      client: MockClient(
        (request) async => jsonResponse({
          'message': 'License unavailable',
          'code': 'license_invalid',
        }, 403),
      ),
    );
    final translations = AppLocalizations(api: api);
    controllers.add(translations);
    await translations.initialize();
    expect(translations.error, isNotNull);
    expect(MobileApi.failure.value, isNull);
    await expectLater(
      api.request('/auth/options', authenticated: false),
      throwsA(isA<ApiFailure>()),
    );
    expect(MobileApi.failure.value, isNotNull);
    MobileApi.failure.value = null;
  });

  test('the selected language accompanies normal API calls without changing their payloads', () async {
    String? selectedHeader;
    final api = MobileApi(
      origin: Uri.parse('https://customer.example.test'),
      store: MemorySecureStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        if (request.url.path.endsWith('/translations')) {
          return jsonResponse(
            catalog(code: request.url.queryParameters['locale'] ?? 'de'),
          );
        }
        selectedHeader = request.headers['Accept-Language'];
        return jsonResponse({'ok': true});
      }),
    );
    final translations = AppLocalizations(api: api);
    controllers.add(translations);
    AppLocalizations.current = translations;
    await translations.initialize();
    await api.request('/auth/options', authenticated: false);
    expect(selectedHeader, 'de');
  });
  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    AppLocalizations.current = previous;
  });

  test('selected translations take precedence over differently cased fallback keys', () async {
    final body = catalog();
    (body['fallback'] as Map)['Sign in'] = 'Sign in';
    (body['fallback'] as Map)['Sign In'] = 'Sign In';
    (body['translations'] as Map)['Sign in'] = 'Anmelden';
    final translations = create((_) async => body);
    await translations.initialize();
    expect(appTr('Sign In'), 'Anmelden');
  });

  test('initial language is the server default and all labels come from the catalog', () async {
    final translations = create((code) async => catalog(code: code ?? 'de'));
    await translations.initialize();
    expect(translations.localeCode, 'de');
    expect(appTr('Save'), 'Speichern');
    expect(
      appTr('The Email field is required.'),
      'Das Feld Email ist erforderlich.',
    );
    expect(appTr('save'), 'Speichern');
    expect(appTr('Hello :name', {'name': 'Lena'}), 'Hallo Lena');
    expect(appTr(':count file|:count files', {}, 3), '3 Dateien');
    expect(appTr('Missing selected'), 'English fallback');
    expect(appTr('Not translated yet'), 'Not translated yet');
  });

  test(
    'the selected language persists after creating a new app instance',
    () async {
      final first = create((code) async => catalog(code: code ?? 'de'));
      await first.initialize();
      await first.select('ar');
      final next = create((code) async => catalog(code: code ?? 'de'));
      await next.initialize();
      expect(next.localeCode, 'ar');
      expect(next.direction, TextDirection.rtl);
      expect(appTr('Save'), 'حفظ');
    },
  );

  test(
    'cached translations and selection remain usable while offline',
    () async {
      final first = create((code) async => catalog(code: code ?? 'de'));
      await first.initialize();
      await first.select('de');
      final offline = create(
        (code) async => throw const FormatException('Offline'),
      );
      await offline.initialize();
      expect(offline.localeCode, 'de');
      expect(offline.translate('Save'), 'Speichern');
      expect(offline.error, isNotNull);
    },
  );

  test('disabled languages disappear and a removed selection falls back to the current admin default', () async {
    var removed = false;
    final translations = create(
      (code) async => removed
          ? catalog(code: 'en', defaultCode: 'en', codes: ['en'])
          : catalog(code: code ?? 'de'),
    );
    await translations.initialize();
    await translations.select('de');
    removed = true;
    await translations.refresh();
    expect(translations.languages.map((language) => language.code), ['en']);
    expect(translations.localeCode, 'en');
    expect(translations.translate('Save'), 'Save');
  });

  test('an unselected app follows changes to the admin default', () async {
    var defaultCode = 'de';
    final translations = create(
      (code) async =>
          catalog(code: code ?? defaultCode, defaultCode: defaultCode),
    );
    await translations.initialize();
    defaultCode = 'ar';
    await translations.refresh();
    expect(translations.localeCode, 'ar');
  });

  test('a late language response cannot overwrite a newer choice', () async {
    final german = Completer<Map<String, dynamic>>();
    final arabic = Completer<Map<String, dynamic>>();
    var delay = false;
    final translations = create(
      (code) async => delay
          ? await (code == 'de' ? german.future : arabic.future)
          : catalog(code: 'en'),
    );
    await translations.initialize();
    delay = true;
    final first = translations.select('de');
    final second = translations.select('ar');
    arabic.complete(catalog(code: 'ar'));
    await second;
    german.complete(catalog(code: 'de'));
    await first;
    expect(translations.localeCode, 'ar');
  });

  test('a failed uncached selection preserves the working language', () async {
    final translations = create((code) async {
      if (code == 'ar') throw const FormatException('Offline');
      return catalog(code: 'de');
    });
    await translations.initialize();
    await translations.select('ar');
    expect(translations.localeCode, 'de');
    expect(translations.translate('Save'), 'Speichern');
  });

  testWidgets(
    'switching updates labels, forms and framework buttons without resetting screen state',
    (tester) async {
      var edited = false;
      final translations = create(
        (code) async => catalog(
          code: code ?? 'en',
          extra: edited ? {'Save': 'Jetzt speichern'} : {},
        ),
      );
      await translations.initialize();
      await tester.pumpWidget(TranslationHost(translations));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      await translations.select('de');
      await tester.pumpAndSettle();
      expect(find.text('Speichern'), findsOneWidget);
      expect(find.text('Einstellungen'), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('user-content'))).data,
        'Save',
      );
      final context = tester.element(find.byType(TranslationPage));
      expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Abbrechen');
      edited = true;
      await translations.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Jetzt speichern'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await translations.select('ar');
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(TranslationPage))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      translations.dispose();
      controllers.remove(translations);
    },
  );

  testWidgets(
    'the reference globe pill lists only server configured languages',
    (tester) async {
      final translations = create(
        (code) async => catalog(code: code ?? 'de', codes: ['en', 'de']),
      );
      await translations.initialize();
      await tester.pumpWidget(TranslationHost(translations));
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
      expect(find.text('DE'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-language-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('ar'), findsNothing);
      await tester.tap(find.text('en').last);
      await tester.pumpAndSettle();
      expect(translations.localeCode, 'en');
      expect(find.text('EN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      translations.dispose();
      controllers.remove(translations);
    },
  );
}
