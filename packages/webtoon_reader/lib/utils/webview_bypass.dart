import 'package:flutter/material.dart';

import '../models/webview_bypass_runner.dart';
import '../screens/webview_bypass_screen.dart';

WebViewBypassRunner createWebViewBypassRunner(BuildContext context) {
  return (url, extractJs, hint) {
    if (!context.mounted) return Future.value(null);
    return Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => WebViewBypassScreen(
          url: url,
          extractJs: extractJs,
          hint: hint,
        ),
      ),
    );
  };
}
