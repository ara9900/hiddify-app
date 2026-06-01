class TikNetFaqItem {
  const TikNetFaqItem({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
  });

  final int id;
  final String category;
  final String question;
  final String answer;

  factory TikNetFaqItem.fromJson(Map<String, dynamic> json) {
    return TikNetFaqItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: (json['category'] as String?) ?? 'general',
      question: (json['question'] as String?) ?? '',
      answer: (json['answer'] as String?) ?? '',
    );
  }
}
