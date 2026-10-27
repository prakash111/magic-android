import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../server_screen.dart';
import '../../services/mobile_api.dart';

class AIWriterScreen extends StatelessWidget {
  const AIWriterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return FutureBuilder<dynamic>(
      future: MobileApi.instance.request('/config'),
      builder: (context, snapshot) {
        AppLocalizations.watch(context);
        if (snapshot.hasError) {
          return Center(child: Text(appTr(snapshot.error.toString())));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tools = (snapshot.data['tools'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        return ToolDirectory(
          tools: tools,
          credits: const {},
          dashboard: false,
          refresh: () async {},
        );
      },
    );
  }
}
