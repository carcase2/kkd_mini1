import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_version.dart';
import '../utils/format.dart';
import '../widgets/timer_ring.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppUpdateInfo? _update;
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    setState(() => _update = info);
  }

  void _goTo(int index) => widget.onNavigate(index);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final fasting = state.activeFasting;
    final abstinence = state.activeAbstinence;
    final reading = state.activeReading;
    final sinceLast = state.timeSinceLastMasturbation;
    final hasMasturbation = state.lastMasturbation != null;
    final todayLabel =
        DateFormat('yyyy년 M월 d일 (E)', 'ko').format(DateTime.now());

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // 업데이트 배너
            if (_update != null && !_updateDismissed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _UpdateBanner(
                    info: _update!,
                    colors: c,
                    onUpdate: () => UpdateService.openUpdate(_update!),
                    onDismiss: _update!.force
                        ? null
                        : () => setState(() => _updateDismissed = true),
                  ),
                ),
              ),

            // 헤더 — 전체 폭 사용
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 오늘 날짜
                    Text(
                      todayLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.fasting,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 제목 + 버전 + 메뉴
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '절제',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    color: c.textPrimary,
                                    height: 1.15,
                                  ),
                                ),
                                TextSpan(
                                  text: '  ${AppVersion.label}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.textMuted,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _HeaderIconButton(
                          colors: c,
                          icon: state.isDarkMode
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_outlined,
                          tooltip: '테마 변경',
                          onTap: () => context.read<AppState>().toggleTheme(),
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          tooltip: '더보기',
                          onSelected: (v) {
                            if (v == 'backup') _showBackupSheet(context);
                            if (v == 'lock') _showLockSettings(context);
                            if (v == 'lock_now') {
                              context.read<AppState>().lockApp();
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'backup',
                              child: Text('백업 · 내보내기'),
                            ),
                            const PopupMenuItem(
                              value: 'lock',
                              child: Text('잠금 · 알림 설정'),
                            ),
                            if (state.lockEnabled)
                              const PopupMenuItem(
                                value: 'lock_now',
                                child: Text('지금 잠그기'),
                              ),
                          ],
                          child: Container(
                            width: 46,
                            height: 46,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.border),
                              boxShadow: appCardShadow(c),
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: c.textSecondary,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '건강한 습관을 기록하는 루틴 앱',
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _greeting(),
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
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
                    startTime: fasting.startTime,
                    showExpectedEnd: true,
                    onTap: () => _goTo(1),
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
                    startTime: abstinence.startTime,
                    showExpectedEnd: true,
                    onTap: () => _goTo(2),
                  ),
                ),
              ),
            if (reading != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _ActiveCard(
                    title: '독서 중 · ${state.bookById(reading.bookId)?.title ?? '책'}',
                    color: c.reading,
                    soft: c.readingSoft,
                    colors: c,
                    elapsed: reading.elapsed,
                    target: Duration(minutes: state.readingDailyGoalMinutes),
                    startTime: reading.startTime,
                    onTap: () => _goTo(3),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _CheckCard(
                  colors: c,
                  hasRecord: hasMasturbation,
                  since: sinceLast,
                  onTap: () => _goTo(4),
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
                      onTap: () => _goTo(1),
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
                      onTap: () => _goTo(2),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '독서',
                      icon: Icons.menu_book_rounded,
                      color: c.reading,
                      soft: c.readingSoft,
                      colors: c,
                      status: reading != null
                          ? '${formatDuration(reading.elapsed, short: true)} 진행'
                          : state.readingTodayGoalMet
                              ? '오늘 목표 달성'
                              : '오늘 ${formatDurationTiny(state.readingToday)}',
                      detail: state.selectedBook != null
                          ? '${state.selectedBook!.title} · 연속 ${state.readingStreak}일'
                          : '주 ${formatDurationTiny(state.readingThisWeek)} · ${state.books.length}권',
                      onTap: () => _goTo(3),
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
                      onTap: () => _goTo(4),
                    ),
                    const SizedBox(height: 8),
                    _QuickRow(
                      title: '약',
                      icon: Icons.medication_rounded,
                      color: c.warning,
                      soft: c.warningSoft,
                      colors: c,
                      status: state.activeMedications.isEmpty &&
                              state.activeMedicationSets.isEmpty
                          ? '등록 없음'
                          : state.medicationDueCount > 0
                              ? '복용 가능 ${state.medicationDueCount}개'
                              : _medicationHomeStatus(state),
                      detail: state.activeMedications.isEmpty &&
                              state.activeMedicationSets.isEmpty
                          ? '약·세트로 복용 시간을 기록하세요'
                          : _medicationHomeDetail(state),
                      onTap: () => _goTo(5),
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
                      onTap: () => _goTo(6),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Center(
                  child: Text(
                    AppVersion.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
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

  Future<void> _showLockSettings(BuildContext context) async {
    final c = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _LockSettingsSheet(),
    );
  }

  Future<void> _showBackupSheet(BuildContext context) async {
    final c = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _BackupSheet(),
    );
  }

  String _medicationHomeStatus(AppState state) {
    final meds = state.activeMedications.length;
    final sets = state.activeMedicationSets.length;
    if (sets > 0 && meds > 0) return '약 $meds · 세트 $sets';
    if (sets > 0) return '세트 $sets개 관리 중';
    return '약 $meds개 관리 중';
  }

  String _medicationHomeDetail(AppState state) {
    Duration? soonest;
    String? name;

    for (final set in state.activeMedicationSets) {
      final until = state.timeUntilNextSetDose(set);
      if (until == null || until <= Duration.zero) {
        return '${set.name} 세트 · 복용 가능';
      }
      if (soonest == null || until < soonest) {
        soonest = until;
        name = '${set.name} 세트';
      }
    }

    for (final med in state.activeMedications) {
      final until = state.timeUntilNextDose(med);
      if (until == null || until <= Duration.zero) {
        return '${med.name} · 복용 가능';
      }
      if (soonest == null || until < soonest) {
        soonest = until;
        name = med.name;
      }
    }

    if (name != null && soonest != null) {
      return '$name · ${formatDuration(soonest, short: true)} 후';
    }
    return '주기별 복용 시간을 기록하세요';
  }
}

class _UpdateBanner extends StatelessWidget {
  final AppUpdateInfo info;
  final AppPalette colors;
  final VoidCallback onUpdate;
  final VoidCallback? onDismiss;

  const _UpdateBanner({
    required this.info,
    required this.colors,
    required this.onUpdate,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.fasting.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onUpdate,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.fasting.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded, color: colors.fasting, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '새 버전 ${info.label} 출시',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.message.isNotEmpty
                          ? info.message
                          : '눌러서 업데이트하기',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onUpdate,
                child: Text(
                  '업데이트',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: colors.fasting,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: '닫기',
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final AppPalette colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
              boxShadow: appCardShadow(colors),
            ),
            child: Icon(icon, color: colors.textSecondary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet();

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  bool _busy = false;
  List<LocalBackupInfo> _locals = [];

  @override
  void initState() {
    super.initState();
    _loadLocals();
  }

  Future<void> _loadLocals() async {
    final list = await BackupService.listLocalBackups();
    if (mounted) setState(() => _locals = list);
  }

  String _formatBackupTime(DateTime? when) {
    if (when == null) return '아직 백업한 적 없음';
    return DateFormat('yyyy.M.d (E) HH:mm', 'ko').format(when);
  }

  String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 30) return '${diff.inDays}일 전';
    return DateFormat('M/d', 'ko').format(when);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      await BackupService.exportToFile(state);
      await _loadLocals();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('백업 파일을 공유할 준비가 됐어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('내보내기 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNowLocal() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BackupService.saveLocalBackup(
        context.read<AppState>(),
        prefix: 'manual',
      );
      await _loadLocals();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기에 백업을 저장했어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('백업 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final c = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('불러올까요?'),
        content: const Text(
          '백업 파일의 내용으로 현재 데이터를 모두 교체합니다.\n'
          '지금 기기 데이터는 덮어씌워지니, 필요하면 먼저 내보내기 하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.fasting),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('불러오기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      final result = await BackupService.importFromFile(state);
      if (!mounted) return;
      if (result == null) return;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('백업을 불러왔어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreLocal(LocalBackupInfo info) async {
    if (_busy) return;
    final c = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 백업으로 복원할까요?'),
        content: Text(
          '${_formatBackupTime(info.modifiedAt)}\n'
          '현재 데이터는 이 백업으로 교체됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.fasting),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.importFromLocalPath(
        context.read<AppState>(),
        info.path,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로컬 백업으로 복원했어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복원 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    final last = state.lastBackupAt;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.import_export_rounded, color: c.fasting),
                  const SizedBox(width: 10),
                  Text(
                    '데이터 백업',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 마지막 백업 시각
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.fasting.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: c.fasting.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: c.fasting,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '마지막 백업',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (last != null)
                          Text(
                            _formatRelative(last),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.fasting,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatBackupTime(last),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: c.textPrimary,
                      ),
                    ),
                    if (state.autoBackupEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        last == null
                            ? '기록(단식·금욕·독서 등)이 생기면 기기에 자동 저장'
                            : '기록 추가·변경 시 자동 저장 (최소 2분 간격)',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 자동 백업 설정 (데이터 변경 시)
              Text(
                '자동 백업',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '데이터 변경 시 자동 백업',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '금욕·독서·단식·체크·약 등이 추가·변경되면 기기에 저장',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                value: state.autoBackupEnabled,
                activeThumbColor: c.fasting,
                onChanged: _busy
                    ? null
                    : (v) => context.read<AppState>().setAutoBackupEnabled(v),
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.fasting,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text(
                  '내보내기 (공유)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.fasting,
                  side: BorderSide(color: c.fasting.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _backupNowLocal,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text(
                  '지금 기기에 백업',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textSecondary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text(
                  '파일에서 불러오기',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    '기기 백업 목록',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_locals.length}개',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_locals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '아직 기기 안에 저장된 백업이 없어요.\n'
                    '「지금 기기에 백업」또는 자동 백업을 켜 보세요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textMuted,
                      height: 1.4,
                    ),
                  ),
                )
              else
                ..._locals.take(8).map((info) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _busy ? null : () => _restoreLocal(info),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                info.name.startsWith('auto')
                                    ? Icons.autorenew_rounded
                                    : Icons.history_rounded,
                                size: 20,
                                color: c.fasting,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatBackupTime(info.modifiedAt),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${_formatRelative(info.modifiedAt)}'
                                      ' · ${(info.sizeBytes / 1024).toStringAsFixed(1)} KB'
                                      '${info.name.startsWith('auto') ? ' · 자동' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '복원',
                                style: TextStyle(
                                  color: c.fasting,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 8),
              Text(
                '· 자동 백업: 기록 추가·변경 시 기기 안 저장 (최대 15개).\n'
                '· 앱 삭제 시 사라집니다. 재설치·기종 변경은 「내보내기」를 쓰세요.',
                style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.45),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LockSettingsSheet extends StatelessWidget {
  const _LockSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final media = MediaQuery.of(context);
    // 시스템 내비/제스처 바와 겹치지 않도록 넉넉히
    final bottomPad =
        40 + media.viewInsets.bottom + media.viewPadding.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.security_rounded, color: c.fasting),
              const SizedBox(width: 10),
              Text(
                '잠금 설정',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '앱 시작·백그라운드 복귀 시 비밀번호로 보호합니다.',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '앱 잠금 사용',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              '켜면 실행 시 비밀번호가 필요합니다',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            value: state.lockEnabled,
            activeThumbColor: c.fasting,
            onChanged: (v) => context.read<AppState>().setLockEnabled(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '자동 잠금',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              '앱을 나가면 자동으로 잠급니다',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            value: state.autoLockEnabled,
            activeThumbColor: c.fasting,
            onChanged: state.lockEnabled
                ? (v) => context.read<AppState>().setAutoLockEnabled(v)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            '세션 알림',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '단식·금욕 진행 알림',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              '절반 지남 · 10% 남음 · 목표 완료 시 알림',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            value: state.sessionNotificationsEnabled,
            activeThumbColor: c.fasting,
            onChanged: (v) =>
                context.read<AppState>().setSessionNotificationsEnabled(v),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.password_rounded, color: c.fasting),
            title: Text(
              '비밀번호 변경',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              '숫자 4~12자리',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted),
            enabled: state.lockEnabled,
            onTap: state.lockEnabled
                ? () => _changePin(context)
                : null,
          ),
          if (state.lockEnabled) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.read<AppState>().lockApp();
              },
              icon: const Icon(Icons.lock_rounded),
              label: const Text(
                '지금 잠그기',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.fasting,
                side: BorderSide(color: c.fasting.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          // 하단 여백 (내비 바와 버튼 사이)
          const SizedBox(height: 24),
        ],
        ),
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final c = AppPalette.of(context);
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '현재 비밀번호'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '새 비밀번호'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.fasting),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    final current = currentCtrl.text.trim();
    final next = newCtrl.text.trim();
    final confirm = confirmCtrl.text.trim();

    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 비밀번호가 일치하지 않습니다')),
      );
      return;
    }
    if (next.length < 4 || next.length > 12 || !RegExp(r'^\d+$').hasMatch(next)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호는 숫자 4~12자리여야 합니다')),
      );
      return;
    }

    final success = await context.read<AppState>().changePin(
          currentPin: current,
          newPin: next,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? '비밀번호를 변경했어요' : '현재 비밀번호가 올바르지 않습니다',
        ),
      ),
    );
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
        (state.activeAbstinence != null ? 1 : 0) +
        (state.activeReading != null ? 1 : 0);

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
                  activeCount > 0
                      ? '아래에서 타이머를 확인하세요'
                      : '단식·금욕·독서를 시작해보세요',
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

/// 홈 카드 텍스트 — 길어도 잘리지 않게 축소
class _CardLine extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _CardLine({
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  final AppPalette colors;
  final bool hasRecord;
  final Duration since;
  final VoidCallback onTap;

  const _CheckCard({
    required this.colors,
    required this.hasRecord,
    required this.since,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colors.check;
    final soft = colors.checkSoft;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.favorite_rounded, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardLine(
                      text: '체크',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: hasRecord
                          ? formatElapsedDayHour(since)
                          : '아직 기록 없음',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (hasRecord) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: '마지막 체크 이후',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textSecondary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ],
          ),
        ),
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
  final DateTime? startTime;
  final bool showExpectedEnd;
  final VoidCallback onTap;

  const _ActiveCard({
    required this.title,
    required this.color,
    required this.soft,
    required this.colors,
    required this.elapsed,
    required this.target,
    this.startTime,
    this.showExpectedEnd = false,
    required this.onTap,
  });

  String? get _expectedEndLabel {
    if (!showExpectedEnd || target == null || startTime == null) return null;
    final end = startTime!.add(target!);
    return '완료 예정 ${DateFormat('M/d (E) HH:mm', 'ko').format(end)}';
  }

  String? get _remainingLabel {
    if (!showExpectedEnd || target == null) return null;
    if (elapsed >= target!) {
      final pct = target!.inSeconds > 0
          ? ((elapsed.inSeconds / target!.inSeconds) * 100).toStringAsFixed(0)
          : null;
      return pct != null ? '$pct% 완료' : '목표 시간 도달';
    }
    final left = target! - elapsed;
    return '남은 시간 ${formatDuration(left, short: true)}';
  }

  @override
  Widget build(BuildContext context) {
    final pct = target != null && target!.inSeconds > 0
        ? ((elapsed.inSeconds / target!.inSeconds) * 100).toStringAsFixed(0)
        : null;
    final expectedEnd = _expectedEndLabel;
    final remaining = _remainingLabel;
    final reached = target != null && elapsed >= target!;

    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: appCardShadow(colors),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TimerRing(
                elapsed: elapsed,
                target: target,
                color: color,
                size: 48,
                compact: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CardLine(
                      text: title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: formatDuration(elapsed, short: true),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _CardLine(
                      text: target != null
                          ? '목표 ${formatTargetDuration(target)}${pct != null ? ' · $pct%' : ''}'
                          : '자유 모드',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textSecondary,
                        height: 1.1,
                      ),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: remaining,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: reached ? colors.success : color,
                          height: 1.1,
                        ),
                      ),
                    ],
                    if (expectedEnd != null && !reached) ...[
                      const SizedBox(height: 2),
                      _CardLine(
                        text: expectedEnd,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
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
