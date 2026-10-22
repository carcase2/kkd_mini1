/// Cloudflare R2 (S3 호환). 만화 전용 버킷 `kkd-webtoon` 만 사용합니다.
class R2Config {
  static const accountId = '2f9c79a0dfef5b6c4833ff6a5ed1c806';
  static const accessKeyId = 'ec6172304bd34646867e2be238f3263f';
  static const secretAccessKey =
      '168428b0517350153fca42a640f45f1f787d60af6277f401f8b841b667ce348c';
  static const bucket = 'kkd-webtoon';
  static const region = 'auto';
  static const objectPrefix = 'webtoon';

  static String get endpointHost => '$accountId.r2.cloudflarestorage.com';

  static String get endpointUrl => 'https://$endpointHost';
}
