/// Supabase 클라이언트 설정 (anon/publishable key — RLS 필수)
/// 웹툰 리더 전용 프로젝트 (coad). kkd_mini1(kkd_count) 과 Auth/DB 완전 분리.
class SupabaseConfig {
  static const url = 'https://jpnracwqvvitcactnmkk.supabase.co';
  /// coad 프로젝트 anon key (publishableKey 파라미터로 전달)
  static const publishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpwbnJhY3dxdnZpdGNhY3RubWtrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk4NzE4NzUsImV4cCI6MjA2NTQ0Nzg3NX0.OA1Cza0z3TWZnSUSahfV0HPmIYbCb2uWAl3RJRtUPCs';
}
