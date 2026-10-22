typedef WebViewBypassRunner = Future<String?> Function(
  String url,
  String extractJs,
  String hint,
);
