import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../services/webview_scripts.dart';

bool get _isCupertinoWebView =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

InAppWebViewSettings createWebViewSettings({bool disableContextMenu = true}) {
  return InAppWebViewSettings(
    // WKWebView must keep the native Safari UA. An Android Chrome UA on
    // iPhone is a common Cloudflare / site-block trigger.
    userAgent: _isCupertinoWebView ? '' : AppConstants.userAgent,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    domStorageEnabled: true,
    useShouldOverrideUrlLoading: false,
    mediaPlaybackRequiresUserGesture: false,
    useHybridComposition: true,
    supportMultipleWindows: false,
    thirdPartyCookiesEnabled: true,
    sharedCookiesEnabled: true,
    isFraudulentWebsiteWarningEnabled: false,
    allowsInlineMediaPlayback: true,
    disableDefaultErrorPage: true,
    preferredContentMode: UserPreferredContentMode.MOBILE,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    disableContextMenu: disableContextMenu,
    isInspectable: kDebugMode,
  );
}

/// iOS fires resource / cancelled errors for ads, redirects, and challenges.
/// Those are not main-page failures and must not stop the reader.
bool shouldIgnoreWebViewError(
  WebResourceRequest request,
  WebResourceError error,
) {
  if (request.isForMainFrame == false) return true;
  if (error.type == WebResourceErrorType.CANCELLED) return true;
  return false;
}

UnmodifiableListView<UserScript> createWebViewUserScripts() {
  return UnmodifiableListView<UserScript>([
    UserScript(
      source: WebViewScripts.captureSsrHtml,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ]);
}

void logRenderProcessGone(
  InAppWebViewController controller,
  RenderProcessGoneDetail detail,
) {
  debugPrint(
    'WebView render process ended (crashed=${detail.didCrash})',
  );
}
