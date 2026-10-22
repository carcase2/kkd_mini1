import '../models/chapter.dart';
import '../models/series.dart';

class TextSearch {
  TextSearch._();

  static String normalize(String value) => value.trim().toLowerCase();

  static bool matches(String text, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) return true;
    return normalize(text).contains(needle);
  }

  static bool chapterMatches(Chapter chapter, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) return true;
    if (matches(chapter.title, needle)) return true;
    if (matches('${chapter.number}', needle)) return true;
    if (matches('${chapter.number}화', needle)) return true;
    final label = chapter.publishedLabel;
    if (label != null && matches(label, needle)) return true;
    return false;
  }

  static List<Series> filterSeries(List<Series> series, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) return series;
    return series.where((item) => matches(item.title, needle)).toList();
  }

  static List<Chapter> filterChapters(List<Chapter> chapters, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) return chapters;
    return chapters.where((item) => chapterMatches(item, needle)).toList();
  }
}
