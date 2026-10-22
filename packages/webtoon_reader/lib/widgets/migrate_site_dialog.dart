import 'package:flutter/material.dart';

import '../models/site_migration_result.dart';
import '../services/storage_service.dart';

Future<SiteMigrationResult?> showMigrateSiteDialog(BuildContext context) {
  return showDialog<SiteMigrationResult>(
    context: context,
    builder: (context) => const _MigrateSiteDialog(),
  );
}

class _MigrateSiteDialog extends StatefulWidget {
  const _MigrateSiteDialog();

  @override
  State<_MigrateSiteDialog> createState() => _MigrateSiteDialogState();
}

class _MigrateSiteDialogState extends State<_MigrateSiteDialog> {
  final _storage = StorageService.instance;
  final _controller = TextEditingController();
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _storage.migrateSiteOrigin(_controller.text);
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message?.toString() ?? '입력을 확인해 주세요';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '변경 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _storage.siteOrigin;

    return AlertDialog(
      title: const Text('사이트 주소 일괄 변경'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '사이트 도메인이 바뀌었을 때 서재·회차·만화 찾기 주소를 한 번에 바꿉니다.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('현재 주소', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              current,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: '새 사이트 주소',
                hintText: 'https://sbxh9.com',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Text(
              '예: sbxh10.com → sbxh9.com\n'
              '변경 후 각 만화에서 회차 목록 새로고침을 권장합니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('일괄 변경'),
        ),
      ],
    );
  }
}
