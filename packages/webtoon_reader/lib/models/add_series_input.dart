class AddSeriesInput {
  const AddSeriesInput({required this.url, this.title});

  final String url;
  final String? title;

  String? get trimmedTitle {
    final value = title?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
