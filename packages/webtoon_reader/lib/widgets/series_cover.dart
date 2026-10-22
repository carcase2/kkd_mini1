import 'dart:io';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/series.dart';

class SeriesCover extends StatelessWidget {
  const SeriesCover({
    super.key,
    required this.series,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.fit = BoxFit.cover,
  });

  final Series series;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final localPath = series.coverPath;
        final remoteUrl = series.coverUrl;
        final initial = series.title.isNotEmpty
            ? series.title.characters.first.toUpperCase()
            : '?';
        final cache = _coverCacheSize(
          context,
          constraints,
          width: width,
          height: height,
        );

        Widget image;
        // existsSync는 경로별 짧게 캐시해 그리드 스크롤 시 디스크 I/O를 줄입니다.
        if (localPath != null && _localCoverExists(localPath)) {
          image = Image.file(
            File(localPath),
            fit: fit,
            width: width,
            height: height,
            cacheWidth: cache.$1,
            cacheHeight: cache.$2,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                _Placeholder(initial: initial, scheme: scheme),
          );
        } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
          image = Image.network(
            remoteUrl,
            fit: fit,
            width: width,
            height: height,
            cacheWidth: cache.$1,
            cacheHeight: cache.$2,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            headers: {
              'User-Agent': AppConstants.userAgent,
              'Referer': _coverReferer(remoteUrl, series.url),
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _Placeholder(
                initial: initial,
                scheme: scheme,
                loading: true,
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                _Placeholder(initial: initial, scheme: scheme),
          );
        } else {
          image = _Placeholder(initial: initial, scheme: scheme);
        }

        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(width: width, height: height, child: image),
        );
      },
    );
  }
}

/// 화면에 보이는 크기로만 디코드합니다. 그리드 카드는 width를 안 넘기므로
/// 레이아웃 크기를 써야 원본 표지를 통째로 풀지 않습니다.
(int?, int?) _coverCacheSize(
  BuildContext context,
  BoxConstraints constraints, {
  double? width,
  double? height,
}) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  int? axis(double? logical, double constraint) {
    final size = logical ?? (constraint.isFinite ? constraint : null);
    if (size == null || size < 2) return null;
    return (size * dpr).round().clamp(1, 1280);
  }

  return (
    axis(width, constraints.maxWidth),
    axis(height, constraints.maxHeight),
  );
}

String _coverReferer(String coverUrl, String pageUrl) {
  final host = Uri.tryParse(coverUrl)?.host.toLowerCase() ?? '';
  if (host.contains('lezhin.com')) {
    return 'https://www.lezhin.com/';
  }
  return pageUrl;
}

final Map<String, bool> _coverExistsCache = {};
DateTime _coverCacheEpoch = DateTime.now();

bool _localCoverExists(String path) {
  // 5분마다 캐시 비움 (파일 삭제/갱신 반영)
  if (DateTime.now().difference(_coverCacheEpoch) >
      const Duration(minutes: 5)) {
    _coverExistsCache.clear();
    _coverCacheEpoch = DateTime.now();
  }
  return _coverExistsCache.putIfAbsent(path, () => File(path).existsSync());
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.initial,
    required this.scheme,
    this.loading = false,
  });

  final String initial;
  final ColorScheme scheme;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.28),
            scheme.secondary.withValues(alpha: 0.14),
            scheme.surfaceContainerHighest,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : Text(
              initial,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: scheme.primary.withValues(alpha: 0.85),
              ),
            ),
    );
  }
}
