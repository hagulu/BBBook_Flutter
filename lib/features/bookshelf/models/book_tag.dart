class BookTag {
  const BookTag({required this.id, required this.name});

  final int id;
  final String name;

  factory BookTag.fromJson(Map<String, dynamic> json) {
    return BookTag(id: json['id'] as int, name: json['name'] as String);
  }
}
