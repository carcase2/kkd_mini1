import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/stat_card.dart';
import '../widgets/sticky_bottom_bar.dart';
import '../widgets/timer_ring.dart';

class ReadingScreen extends StatelessWidget {
  const ReadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final active = state.activeReading;
    final selected = state.selectedBook;
    final books = state.sortedBooks;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.readingSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: c.reading,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '독서',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  '시작 → 읽기 → 종료, 끝!',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '하루 목표',
                            onPressed: () => _editDailyGoal(context),
                            icon: Icon(
                              Icons.flag_outlined,
                              color: c.textSecondary,
                            ),
                          ),
                          IconButton(
                            tooltip: '책 추가',
                            onPressed: () => _showBookEditor(context),
                            icon: Icon(Icons.add_rounded, color: c.reading),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 오늘 목표 진행
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: _TodayGoalCard(state: state, colors: c),
                    ),
                  ),

                  // 활성 타이머 또는 안내
                  if (active != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: _ActiveReadingCard(
                          state: state,
                          log: active,
                          colors: c,
                        ),
                      ),
                    )
                  else if (books.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: _EmptyBooks(
                          colors: c,
                          onAdd: () => _showBookEditor(context),
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: _QuickStartHint(
                          colors: c,
                          lastBook: selected,
                          bookCount: books.length,
                        ),
                      ),
                    ),

                  // 통계 칩
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: StatsRow(
                        chips: [
                          QuickStatChip(
                            label: '연속',
                            value: '${state.readingStreak}일',
                            color: c.reading,
                          ),
                          QuickStatChip(
                            label: '이번 주',
                            value: formatDurationTiny(state.readingThisWeek),
                            color: c.success,
                          ),
                          QuickStatChip(
                            label: '총 시간',
                            value: formatDurationTiny(state.readingTotalTime),
                            color: c.warning,
                          ),
                          QuickStatChip(
                            label: '완독',
                            value: '${state.booksCompletedCount}',
                            color: c.abstinence,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 달력
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: _ReadingCalendar(
                        minutesByDay: state.readingMinutesByDay,
                        colors: c,
                      ),
                    ),
                  ),

                  // 내 책장
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            '내 책장',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (active == null && books.isNotEmpty)
                            Text(
                              '탭하면 바로 시작',
                              style: TextStyle(
                                color: c.reading,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            '${books.length}권',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (books.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          '책을 등록하고 읽기 시작해보세요.',
                          style: TextStyle(color: c.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final book = books[index];
                            final selectedId = state.selectedBookId;
                            final isActiveBook =
                                active != null && active.bookId == book.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _BookTile(
                                book: book,
                                state: state,
                                colors: c,
                                isSelected: book.id == selectedId || isActiveBook,
                                isReadingNow: isActiveBook,
                                onSelect: () {
                                  if (active != null) {
                                    // 진행 중에는 선택만
                                    context
                                        .read<AppState>()
                                        .setSelectedBookId(book.id);
                                    return;
                                  }
                                  // 탭 = 그 책으로 바로 시작
                                  _startReading(context, bookId: book.id);
                                },
                                onEdit: () =>
                                    _showBookEditor(context, book: book),
                                onDelete: () =>
                                    _deleteBook(context, book),
                              ),
                            );
                          },
                          childCount: books.length,
                        ),
                      ),
                    ),

                  // 최근 기록
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            '최근 기록',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _showManualLog(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '수동 기록',
                              style: TextStyle(
                                color: c.reading,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (state.completedReadingLogs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        child: Center(
                          child: Text(
                            '아직 독서 기록이 없어요.',
                            style: TextStyle(color: c.textMuted),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final log = state.completedReadingLogs[index];
                            final book = state.bookById(log.bookId);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ReadingLogTile(
                                log: log,
                                bookTitle: book?.title ?? '삭제된 책',
                                colors: c,
                                onDelete: () =>
                                    _deleteLog(context, log.id),
                              ),
                            );
                          },
                          childCount: state.completedReadingLogs.length.clamp(
                            0,
                            30,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 고정 하단 액션 — 시작 / 종료 한 번에
            StickyBottomBar(
              child: active != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StickyActionButton(
                          label: '종료 · 기록',
                          icon: Icons.stop_rounded,
                          color: c.reading,
                          onTap: () => _endReading(context),
                        ),
                        const SizedBox(height: 2),
                        TextButton(
                          onPressed: () => _cancelReading(context),
                          child: Text(
                            '기록 없이 취소',
                            style: TextStyle(
                              color: c.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )
                  : StickyActionButton(
                      label: books.isEmpty ? '책 등록 후 시작' : '독서 시작',
                      icon: books.isEmpty
                          ? Icons.add_rounded
                          : Icons.play_arrow_rounded,
                      color: c.reading,
                      onTap: () => _quickStart(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 원탭 시작: 책 없으면 등록 → 1권이면 바로 시작 → 여러 권이면 선택 즉시 시작
  Future<void> _quickStart(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.activeReading != null) return;

    var books = state.sortedBooks;
    if (books.isEmpty) {
      await _showBookEditor(context);
      if (!context.mounted) return;
      books = context.read<AppState>().sortedBooks;
      if (books.isEmpty) return;
      // 방금 등록한 책으로 바로 시작
      await _startReading(context, bookId: books.first.id);
      return;
    }

    if (books.length == 1) {
      await _startReading(context, bookId: books.first.id);
      return;
    }

    // 여러 권: 선택하면 바로 시작
    final bookId = await _pickBook(
      context,
      title: '어떤 책을 읽을까요?',
      startOnSelect: true,
    );
    if (bookId != null && context.mounted) {
      await _startReading(context, bookId: bookId);
    }
  }

  Future<void> _startReading(
    BuildContext context, {
    String? bookId,
  }) async {
    HapticFeedback.mediumImpact();
    await context.read<AppState>().startReading(bookId: bookId);
    if (context.mounted) {
      final book = context.read<AppState>().bookById(
            bookId ?? context.read<AppState>().selectedBookId ?? '',
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            book != null ? '「${book.title}」 독서 시작 📖' : '독서를 시작했어요 📖',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _cancelReading(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 없이 취소할까요?'),
        content: const Text('지금까지의 시간은 저장되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 읽기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('취소', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().cancelReading();
    }
  }

  /// 종료 = 읽은 시간만 바로 기록
  Future<void> _endReading(BuildContext context) async {
    final state = context.read<AppState>();
    final active = state.activeReading;
    if (active == null) return;

    final book = state.bookById(active.bookId);
    final elapsed = active.elapsed;
    final c = AppPalette.of(context);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('독서 종료'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book?.title ?? '책',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatDuration(elapsed, short: true)} 읽었어요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: c.reading,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '이 시간으로 기록할까요?',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'back'),
            child: const Text('계속 읽기'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.reading),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('기록'),
          ),
        ],
      ),
    );

    if (action != 'save' || !context.mounted) return;

    HapticFeedback.mediumImpact();
    await state.endReading();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '독서 ${formatDuration(elapsed, short: true)} 기록했어요 📖',
          ),
        ),
      );
    }
  }

  Future<void> _editDailyGoal(BuildContext context) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(
      text: '${state.readingDailyGoalMinutes}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('하루 독서 목표'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '목표 시간 (분)',
            suffixText: '분',
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final m = int.tryParse(controller.text) ?? 30;
      await state.setReadingDailyGoalMinutes(m);
    }
  }

  /// 책 선택 시트. [startOnSelect]이면 탭한 책 id 반환(즉시 시작용).
  Future<String?> _pickBook(
    BuildContext context, {
    String title = '읽을 책 선택',
    bool startOnSelect = false,
  }) async {
    final state = context.read<AppState>();
    final books = state.sortedBooks;
    if (books.isEmpty) {
      await _showBookEditor(context);
      return context.mounted
          ? context.read<AppState>().selectedBookId
          : null;
    }
    final c = AppPalette.of(context);
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final nav = MediaQuery.of(ctx).viewPadding.bottom;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _showBookEditor(context);
                    },
                    child: Text(
                      '새 책',
                      style: TextStyle(
                        color: c.reading,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (startOnSelect)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '책을 누르면 바로 시작해요',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.reading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: books.length,
                itemBuilder: (context, i) {
                  final b = books[i];
                  final isSel = b.id == state.selectedBookId;
                  return ListTile(
                    leading: Icon(
                      startOnSelect
                          ? Icons.play_circle_outline_rounded
                          : Icons.menu_book_rounded,
                      color: isSel || startOnSelect ? c.reading : c.textMuted,
                    ),
                    title: Text(
                      b.title,
                      style: TextStyle(
                        fontWeight:
                            isSel ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (b.author != null) b.author!,
                        bookStatusLabel(b.status),
                      ].join(' · '),
                    ),
                    trailing: startOnSelect
                        ? Icon(Icons.chevron_right_rounded, color: c.reading)
                        : (isSel
                            ? Icon(Icons.check_circle, color: c.reading)
                            : null),
                    onTap: () => Navigator.pop(ctx, b.id),
                  );
                },
              ),
            ),
            SizedBox(height: 8 + nav),
          ],
        );
      },
    );
  }

  Future<void> _showBookEditor(BuildContext context, {Book? book}) async {
    final c = AppPalette.of(context);
    final titleCtrl = TextEditingController(text: book?.title ?? '');
    final authorCtrl = TextEditingController(text: book?.author ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final keyboard = media.viewInsets.bottom;
        final navBar = media.viewPadding.bottom;
        final maxH = media.size.height * 0.9;
        // 키보드 또는 시스템 내비 바 + 여유 여백 (등록 버튼이 가리지 않도록)
        final bottomPad = 28 + keyboard + navBar;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                Text(
                  book == null ? '책 등록' : '책 수정',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  book == null
                      ? '등록하면 바로 읽는 중으로 시작해요. 완독은 나중에 책장에서 처리할 수 있어요.'
                      : '제목·저자를 수정할 수 있어요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '제목 *',
                    hintText: '책 제목',
                  ),
                  textInputAction: TextInputAction.next,
                  autofocus: book == null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: authorCtrl,
                  decoration: const InputDecoration(
                    labelText: '저자',
                    hintText: '선택',
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.reading,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    if (titleCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, true);
                  },
                  child: Text(
                    book == null ? '등록' : '저장',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved != true || !context.mounted) return;
    final state = context.read<AppState>();
    if (book == null) {
      await state.addBook(
        title: titleCtrl.text,
        author: authorCtrl.text,
        status: BookStatus.reading,
      );
    } else {
      // 수정 시 기존 상태 유지 (완독은 책장 메뉴에서)
      await state.updateBook(
        book.copyWith(
          title: titleCtrl.text,
          author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text,
          clearAuthor: authorCtrl.text.trim().isEmpty,
        ),
      );
    }
  }

  Future<void> _deleteBook(BuildContext context, Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('책을 삭제할까요?'),
        content: Text('「${book.title}」와 관련 독서 기록이 모두 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteBook(book.id);
    }
  }

  Future<void> _deleteLog(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteReadingLog(id);
    }
  }

  Future<void> _showManualLog(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 책을 등록해주세요')),
      );
      return;
    }
    final c = AppPalette.of(context);
    var bookId = state.selectedBookId ?? state.books.first.id;
    final minutesCtrl = TextEditingController(text: '20');
    final noteCtrl = TextEditingController();
    var when = DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final media = MediaQuery.of(ctx);
            final bottom = media.viewInsets.bottom;
            final maxH = media.size.height * 0.9;
            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                        Text(
                          '수동 독서 기록',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: bookId,
                          decoration: const InputDecoration(labelText: '책'),
                          items: state.sortedBooks
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(
                                    b.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModal(() => bookId = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: minutesCtrl,
                          decoration: const InputDecoration(
                            labelText: '읽은 시간 (분)',
                            suffixText: '분',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('날짜/시간'),
                          subtitle: Text(
                            DateFormat('M월 d일 (E) a h:mm', 'ko').format(when),
                          ),
                          trailing: Icon(Icons.edit_calendar, color: c.reading),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: when,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (d == null || !ctx.mounted) return;
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(when),
                            );
                            if (t == null) return;
                            setModal(() {
                              when = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                t.hour,
                                t.minute,
                              );
                            });
                          },
                        ),
                        TextField(
                          controller: noteCtrl,
                          decoration: const InputDecoration(
                            labelText: '메모 (선택)',
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.reading,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            '기록',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !context.mounted) return;
    final minutes = int.tryParse(minutesCtrl.text) ?? 0;
    if (minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('읽은 시간(분)을 입력해주세요')),
      );
      return;
    }
    await state.logReadingManual(
      bookId: bookId,
      when: when,
      durationMinutes: minutes,
      note: noteCtrl.text,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('독서 기록을 저장했어요')),
      );
    }
  }
}

class _TodayGoalCard extends StatelessWidget {
  final AppState state;
  final AppPalette colors;

  const _TodayGoalCard({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final progress = state.readingTodayGoalProgress;
    final today = state.readingToday;
    final goal = state.readingDailyGoalMinutes;
    final met = state.readingTodayGoalMet;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.reading.withValues(alpha: 0.18),
            colors.readingSoft,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.reading.withValues(alpha: 0.3)),
        boxShadow: appCardShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                met ? Icons.emoji_events_rounded : Icons.today_rounded,
                color: colors.reading,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  met ? '오늘 목표 달성! 🎉' : '오늘의 독서',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${today.inMinutes}/$goal분',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.reading,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.surface.withValues(alpha: 0.7),
              color: colors.reading,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '오늘 ${formatDuration(today, short: true)}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (state.readingStreak > 0)
                Text(
                  '🔥 ${state.readingStreak}일 연속',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.reading,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveReadingCard extends StatelessWidget {
  final AppState state;
  final ReadingLog log;
  final AppPalette colors;

  const _ActiveReadingCard({
    required this.state,
    required this.log,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final book = state.bookById(log.bookId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.reading.withValues(alpha: 0.35)),
        boxShadow: appCardShadow(colors),
      ),
      child: Row(
        children: [
          TimerRing(
            elapsed: log.elapsed,
            target: Duration(minutes: state.readingDailyGoalMinutes),
            color: colors.reading,
            size: 72,
            compact: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '독서 중',
                  style: TextStyle(
                    color: colors.reading,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  book?.title ?? '책',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  formatDuration(log.elapsed, short: true),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: colors.reading,
                  ),
                ),
                Text(
                  '시작 ${DateFormat('HH:mm').format(log.startTime)}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBooks extends StatelessWidget {
  final AppPalette colors;
  final VoidCallback onAdd;

  const _EmptyBooks({required this.colors, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined, size: 48, color: colors.reading),
          const SizedBox(height: 12),
          Text(
            '아직 등록된 책이 없어요',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '읽고 있는 책을 등록하고\n매일 조금씩 이어가 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: colors.reading),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('첫 책 등록'),
          ),
        ],
      ),
    );
  }
}


class _QuickStartHint extends StatelessWidget {
  final AppPalette colors;
  final Book? lastBook;
  final int bookCount;

  const _QuickStartHint({
    required this.colors,
    required this.lastBook,
    required this.bookCount,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = lastBook != null
        ? '최근 「${lastBook!.title}」 · 아래 책을 탭하거나 시작 버튼'
        : bookCount == 1
            ? '아래 시작 버튼 한 번이면 바로 읽어요'
            : '시작 버튼 → 책 고르면 바로 타이머 시작';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.readingSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.reading.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.play_arrow_rounded, color: colors.reading, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '간편 독서',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingCalendar extends StatelessWidget {
  final Map<DateTime, int> minutesByDay;
  final AppPalette colors;

  const _ReadingCalendar({
    required this.minutesByDay,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // 월요일=0 기준 시작 오프셋
    final startWeekday = (monthStart.weekday - 1) % 7;
    final cells = startWeekday + daysInMonth;
    final rows = ((cells + 6) ~/ 7);

    final maxMin = minutesByDay.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: appCardShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 18, color: colors.reading),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${now.year}년 ${now.month}월',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '진할수록 오래 읽음',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellW = (constraints.maxWidth / 7).floorToDouble();
              return Column(
                children: [
                  Row(
                    children: ['월', '화', '수', '목', '금', '토', '일']
                        .map(
                          (d) => SizedBox(
                            width: cellW,
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  for (var r = 0; r < rows; r++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: List.generate(7, (c) {
                          final idx = r * 7 + c;
                          final dayNum = idx - startWeekday + 1;
                          if (dayNum < 1 || dayNum > daysInMonth) {
                            return SizedBox(width: cellW, height: 36);
                          }
                          final day = DateTime(now.year, now.month, dayNum);
                          final mins = minutesByDay[day] ?? 0;
                                                    final isToday = dayNum == now.day;
                          final intensity = maxMin <= 0
                              ? 0.0
                              : (mins / maxMin).clamp(0.0, 1.0);

                          Color bg;
                          if (mins <= 0) {
                            bg = colors.chipBg;
                          } else {
                            bg = Color.lerp(
                                  colors.readingSoft,
                                  colors.reading,
                                  0.25 + intensity * 0.75,
                                ) ??
                                colors.reading;
                          }

                          return SizedBox(
                            width: cellW,
                            height: 36,
                            child: Tooltip(
                              message: mins > 0
                                  ? '$dayNum일 · $mins분'
                                  : '$dayNum일 · 기록 없음',
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isToday
                                      ? Border.all(
                                          color: colors.reading,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: mins > 0 && intensity > 0.45
                                        ? Colors.white
                                        : colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Book book;
  final AppState state;
  final AppPalette colors;
  final bool isSelected;
  final bool isReadingNow;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BookTile({
    required this.book,
    required this.state,
    required this.colors,
    required this.isSelected,
    this.isReadingNow = false,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final time = state.readingTimeForBook(book.id);

    return Material(
      color: isSelected ? colors.readingSoft : colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onSelect,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colors.reading.withValues(alpha: 0.45)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.reading.withValues(alpha: 0.15)
                      : colors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isReadingNow
                      ? Icons.play_arrow_rounded
                      : book.status == BookStatus.completed
                          ? Icons.verified_rounded
                          : Icons.menu_book_outlined,
                  color: isSelected || isReadingNow
                      ? colors.reading
                      : colors.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (isReadingNow) '읽는 중',
                        if (!isReadingNow) bookStatusLabel(book.status),
                        if (book.author != null) book.author!,
                        if (time > Duration.zero)
                          formatDuration(time, short: true),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: isReadingNow
                            ? colors.reading
                            : colors.textSecondary,
                        fontWeight:
                            isReadingNow ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isReadingNow)
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: colors.reading.withValues(alpha: 0.7),
                  size: 22,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                  if (v == 'complete') {
                    context
                        .read<AppState>()
                        .setBookStatus(book.id, BookStatus.completed);
                  }
                  if (v == 'reading') {
                    context
                        .read<AppState>()
                        .setBookStatus(book.id, BookStatus.reading);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('수정')),
                  if (book.status != BookStatus.completed)
                    const PopupMenuItem(
                      value: 'complete',
                      child: Text('완독 처리'),
                    ),
                  if (book.status == BookStatus.completed)
                    const PopupMenuItem(
                      value: 'reading',
                      child: Text('다시 읽기'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingLogTile extends StatelessWidget {
  final ReadingLog log;
  final String bookTitle;
  final AppPalette colors;
  final VoidCallback onDelete;

  const _ReadingLogTile({
    required this.log,
    required this.bookTitle,
    required this.colors,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = log.endTime ?? log.startTime;
    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: colors.dangerSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: colors.danger),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: colors.reading),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    DateFormat('M/d (E) HH:mm', 'ko').format(t),
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDuration(log.recordedDuration, short: true),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: colors.reading,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
