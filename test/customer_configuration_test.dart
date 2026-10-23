import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/storage_service.dart';
import 'package:magicai_mobile/theme/brand_config.dart';

import 'mobile_api_test.dart' show MemorySecureStore;

void main() {
  test('all mobile services share the configured backend', () async {
    expect(StorageService.defaultServerUrl, BrandConfig.serverUrl);
    expect(MobileApi.instance.origin.toString(), BrandConfig.serverUrl);
  });
  test('custom installations use their own HTTPS origin', () {
    final api = MobileApi(origin: Uri.parse('https://customer.example.test'));
    expect(
      api.uri('/auth/profile').toString(),
      'https://customer.example.test/api/mobile/v1/auth/profile',
    );
  });
  test(
    'different customer backends never share stored bearer tokens',
    () async {
      final store = MemorySecureStore();
      final first = TenantSecureStore(
        store,
        Uri.parse('https://first.example.test'),
      );
      final second = TenantSecureStore(
        store,
        Uri.parse('https://second.example.test'),
      );
      await first.write('access_token', 'first-only-token');
      expect(await second.read('access_token'), isNull);
      await second.write('access_token', 'second-only-token');
      expect(await first.read('access_token'), 'first-only-token');
      expect(await second.read('access_token'), 'second-only-token');
    },
  );
  test('tenant namespaces persist across store wrapper instances', () async {
    final store = MemorySecureStore();
    final origin = Uri.parse('https://customer.example.test');
    await TenantSecureStore(store, origin).write('access_token', 'saved-token');
    expect(
      await TenantSecureStore(store, origin).read('access_token'),
      'saved-token',
    );
  });
  test(
    'legacy unscoped credentials are never reused for another backend',
    () async {
      final store = MemorySecureStore()
        ..values['access_token'] = 'legacy-token';
      expect(
        await TenantSecureStore(
          store,
          Uri.parse('https://customer.example.test'),
        ).read('access_token'),
        isNull,
      );
    },
  );
  test('unsafe backend origins cannot receive credentials', () {
    for (final url in [
      '',
      'http://customer.example.test',
      'https://user:password@customer.example.test',
      'https://customer.example.test/subdirectory',
      'https://customer.example.test?key=value',
    ]) {
      final api = MobileApi(origin: Uri.parse(url));
      expect(() => api.uri('/auth/login'), throwsA(isA<ApiFailure>()));
    }
  });
}
