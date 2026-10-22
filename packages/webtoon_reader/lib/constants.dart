class AppConstants {
  static const defaultSiteOrigin = 'https://sbxh9.com';

  /// 회차/표지 HTTP 요청 시 순서대로 시도할 미러 목록입니다.
  static const chapterFetchOrigins = [
    'https://sbxh9.com',
  ];

  /// Host error / 접근 불가 미러입니다. 저장·웹뷰에서도 기본 사이트로 바꿉니다.
  static const blockedFetchHosts = {
    'sbxh10.com',
    'sbxh6.com',
  };

  static const legacySeriesUrl =
      'https://sbxh9.com/webtoon/u-tt-Became_an_apartment_manager-mp14appe-01ho';
  static const legacySeriesId = 'u-tt-Became_an_apartment_manager-mp14appe-01ho';
  static const legacySeriesTitle = 'Became an apartment manager';

  /// [StorageService.siteOrigin] 사용을 권장합니다.
  static const browseCatalogBaseUrl = '$defaultSiteOrigin/ing?cat=adult&sort=hot';

  /// HTTP 다운로드·Android WebView용. iOS WKWebView는 기본 Safari UA를 씁니다.
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36';
}
