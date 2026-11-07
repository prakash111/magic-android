import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

void main() {
  test(
    'Inbox requests advertise all channels after license bootstrap',
    () async {
      final store = MemorySecureStore()
        ..values.addAll({
          'access_token': 'private-token',
          'instance_hash': 'a' * 64,
        });
      var checked = false;
      final api = MobileApi(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/license')) {
            return jsonResponse(license());
          }
          expect(request.headers['X-Mobile-Inbox-Channels'], 'all');
          checked = true;
          return jsonResponse({'all': 0});
        }),
      );
      await api.request('/inbox/counts');
      expect(checked, isTrue);
    },
  );
}
