import 'dart:async';

import 'mobile_api.dart';

class StartupService {
  final MobileApi api;

  const StartupService({required this.api});

  Future<bool> restoreSession() async {
    await api.bootstrap().timeout(const Duration(seconds: 30));
    final token = await api.store
        .read('access_token')
        .timeout(const Duration(seconds: 5));
    if (token == null || token.isEmpty) return false;

    try {
      await api
          .request('/auth/profile', notifyAuthFailure: false)
          .timeout(const Duration(seconds: 12));
    } on ApiFailure catch (problem) {
      if (problem.code == 'license_invalid') rethrow;
      if (problem.status == 401) {
        await api.clearSession().timeout(const Duration(seconds: 15));
        return false;
      }
      // The dashboard provides its own retry view for temporary server failures.
    } on TimeoutException {
      // A slow profile request must not prevent the dashboard from opening.
    }
    return true;
  }
}
