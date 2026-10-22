import 'package:flutter/material.dart';

import '../models/add_series_input.dart';

Future<AddSeriesInput?> showAddSeriesDialog(BuildContext context) {
  final urlController = TextEditingController();
  final titleController = TextEditingController();

  return showDialog<AddSeriesInput>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('만화 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '아파트 관리인이 되었다',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '만화 링크',
                hintText: 'https://sbxh9.com/webtoon/...',
              ),
              keyboardType: TextInputType.url,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Text(
              '제목을 비우면 사이트에서 자동으로 가져옵니다.\n'
              '링크는 브라우저 주소창 전체를 붙여 넣으세요. (-뒤 해시까지)\n'
              '회차는 만화 화면에서 목록 불러온 뒤 체크해서 받으세요.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final url = urlController.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(
              context,
              AddSeriesInput(
                url: url,
                title: titleController.text.trim(),
              ),
            );
          },
          child: const Text('추가'),
        ),
      ],
    ),
  );
}

Future<AddSeriesInput?> showRelinkSeriesDialog(
  BuildContext context, {
  required String currentUrl,
  required String currentTitle,
}) {
  final urlController = TextEditingController(text: currentUrl);
  final titleController = TextEditingController(text: currentTitle);

  return showDialog<AddSeriesInput>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('링크 / 제목 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '링크가 깨졌을 때 새 URL을 입력하세요.\n기존 저장 회차는 유지되고, 새 회차만 목록에 추가됩니다.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: '만화 링크'),
              keyboardType: TextInputType.url,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final url = urlController.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(
              context,
              AddSeriesInput(
                url: url,
                title: titleController.text.trim(),
              ),
            );
          },
          child: const Text('저장'),
        ),
      ],
    ),
  );
}

Future<String?> showEditTitleDialog(
  BuildContext context, {
  required String currentTitle,
}) {
  final controller = TextEditingController(text: currentTitle);

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('제목 수정'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: '제목'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final title = controller.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, title);
          },
          child: const Text('저장'),
        ),
      ],
    ),
  );
}
