import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../services/mobile_api.dart';

Future<void> openAuthPage(
  BuildContext context,
  MobileApi api,
  String path,
) async {
  if (!const ['/forgot-password', '/terms', '/privacy-policy'].contains(path)) {
    return;
  }
  try {
    final url = api.origin.resolve(path);
    await SecureStore.invokeMethod<void>('openUrl', {
      'url': url.toString(),
    }).timeout(const Duration(seconds: 10));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appTr('Unable to open this page. Please retry.')),
        ),
      );
    }
  }
}
