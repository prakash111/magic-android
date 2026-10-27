import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../server_screen.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return ServerListScreen(path: '/documents', title: appTr('Documents'));
  }
}
