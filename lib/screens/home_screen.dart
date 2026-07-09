import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/timer_ring.dart';

class HomeScreen extends StatelessWidget {
  final void Function(int tabIndex) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final fasting = state.activeFasting;
    final abstinence = state.activeAbstinence;
    final sinceLast = state.timeSinceLastMasturbation;
    final hasMasturbation = state.lastMasturbation != null;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '절제',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '건강한 습관을 기록하는 루틴 앱',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _greeting(),
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 테마 토글
                    Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => context.read<AppState>().toggleTheme(),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.border),
                            boxShadow: appCardShadow(c),
                          ),
                          child: Icon(
                            state.isDarkMode
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_outlined,
                            color: c.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _OverviewBanner(state: state, colors: c),
              ),
            ),
            if (fasting != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _ActiveCard(
                    title: '단식 진행 중',
                    color: c.fasting,
                    soft: c.fastingSoft,
                    colors: c,
                    elapsed: fasting.elapsed,
                    target: fasting.targetDuration,
                    onTap: () => onNavigate(1),
                  ),
                ),
              ),
            if (abstinence != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _ActiveCard(
                    title: '금욕 진행 중',
                    color: c.abstinence,
                    soft: c.abstinenceSoft,
                    colors: c,
                    elapsed: abstinence.elapsed,
                    target: abstinence.targetDuration,
                    onTap: () => onNavigate(2),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '빠른 현황',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            // 빠른 현황 — 가로 한 줄 리스트
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _QuickRow(
                      title: '단식',
                      icon: Icons.restaurant_outlined,
                      color: c.fasting,
                      soft: c.fastingSoft,
                      colors: c,
                      status: fasting != null
                          ? '${formatDuration(fasting.elapsed, short: true)} 진행'
                          : '대기 중',
                      detail:
                          '성공 ${state.fastingSuccess} · 실패 ${state.fastingFailed} · 총 ${state.fastingTotal}회',
                      onTap: () => onNavigate(1),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '금욕',
                      icon: Icons.shield_outlined,
                      color: c.abstinence,
                      soft: c.abstinenceSoft,
                      colors: c,
                      status: abstinence != null
                          ? '${formatDuration(abstinence.elapsed, short: true)} 진행'
                          : '대기 중',
                      detail:
                          '성공 ${state.abstinenceSuccess} · 실패 ${state.abstinenceFailed} · 총 ${state.abstinenceTotal}회',
                      onTap: () => onNavigate(2),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '체크',
                      icon: Icons.favorite_border_rounded,
                      color: c.check,
                      soft: c.checkSoft,
                      colors: c,
                      status: hasMasturbation
                          ? formatElapsedDayHour(sinceLast)
                          : '기록 없음',
                      detail:
                          '주 ${state.masturbationThisWeek}회 · 월 ${state.masturbationThisMonth}회',
                      onTap: () => onNavigate(3),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '통계',
                      icon: Icons.insights_rounded,
                      color: c.success,
                      soft: c.successSoft,
                      colors: c,
                      status:
                          '단식 성공 ${formatPercent(state.fastingSuccessRate)}',
                      detail:
                          '금욕 성공 ${formatPercent(state.abstinenceSuccessRate)}',
                      onTap: () => onNavigate(4),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '늦은 밤에도 꾸준히 💪';
    if (h < 12) return '좋은 아침이에요 ☀️';
    if (h < 18) return '오늘도 한 걸음씩 🔥';
    return '저녁 루틴 체크해볼까요 🌙';
  }
}

class _OverviewBanner extends StatelessWidget {
  final AppState state;
  final AppPalette colors;
  const _OverviewBanner({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final activeCount =
        (state.activeFasting != null ? 1 : 0) +
        (state.activeAbstinence != null ? 1 : 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.fasting.withValues(alpha: 0.14),
            colors.abstinence.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: appCardShadow(colors),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: appCardShadow(colors),
            ),
            child: Icon(Icons.bolt_rounded, color: colors.fasting, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activeCount > 0
                      ? '챌린지 $activeCount개 진행 중'
                      : '진행 중인 챌린지 없음',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  activeCount > 0 ? '아래에서 타이머를 확인하세요' : '단식·금욕을 시작해보세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final String title;
  final Color color;
  final Color soft;
  final AppPalette colors;
  final Duration elapsed;
  final Duration? target;
  final VoidCallback onTap;

  const _ActiveCard({
    required this.title,
    required this.color,
    required this.soft,
    required this.colors,
    required this.elapsed,
    required this.target,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target != null && target!.inSeconds > 0
        ? ((elapsed.inSeconds / target!.inSeconds).clamp(0, 1) * 100)
            .toStringAsFixed(0)
        : null;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            children: [
              TimerRing(
                elapsed: elapsed,
                target: target,
                color: color,
                size: 64,
                compact: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDuration(elapsed, short: true),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target != null
                          ? '목표 ${formatTargetDuration(target)}${pct != null ? ' · $pct%' : ''}'
                          : '자유 모드',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// 빠른 현황 — 제목 아래 상세 (잘림 없음)
/// [아이콘]  단식
///          대기 중
///          성공 0 · 실패 1 · 총 1회  ›
class _QuickRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Color soft;
  final AppPalette colors;
  final String status;
  final String detail;
  final VoidCallback onTap;

  const _QuickRow({
    required this.title,
    required this.icon,
    required this.color,
    required this.soft,
    required this.colors,
    required this.status,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: color,
                        height: 1.2,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: colors.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
