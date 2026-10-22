import '../constants.dart';

class SiteUrl {
  SiteUrl._();

  /// `https://sbxh9.com` 형태로 정규화합니다.
  static String normalizeOrigin(String input) {
    final base = _normalizeOriginRaw(input);
    if (base.isEmpty) return base;
    return preferAllowedOrigin(base);
  }

  static String _normalizeOriginRaw(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.parse(trimmed);
    if (uri.host.isEmpty) return trimmed;

    return Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static String? hostOf(String originOrUrl) {
    return Uri.tryParse(originOrUrl)?.host;
  }

  /// [oldHost]와 같은 호스트만 [newOrigin] 기준으로 바꿉니다.
  static String rewriteHost(String url, String oldHost, String newOrigin) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != oldHost) return url;

    final newBase = Uri.parse(_normalizeOriginRaw(newOrigin));
    return uri
        .replace(
          scheme: newBase.scheme,
          host: newBase.host,
          port: newBase.hasPort ? newBase.port : null,
        )
        .toString();
  }

  /// Host error가 나는 차단 미러를 기본 사이트로 바꿉니다.
  static String preferAllowedHost(
    String url, {
    String preferredOrigin = AppConstants.defaultSiteOrigin,
  }) {
    final host = hostOf(url);
    if (host == null || host.isEmpty) return url;
    if (!AppConstants.blockedFetchHosts.contains(host)) return url;
    return rewriteHost(url, host, preferredOrigin);
  }

  static String preferAllowedOrigin(
    String origin, {
    String preferredOrigin = AppConstants.defaultSiteOrigin,
  }) {
    return preferAllowedHost(origin, preferredOrigin: preferredOrigin);
  }

  static String browseCatalogUrl(String siteOrigin) {
    final base = normalizeOrigin(siteOrigin);
    return '$base/ing?cat=adult&sort=hot';
  }
}
