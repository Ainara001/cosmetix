class Review {
  const Review({
    required this.id,
    required this.productId,
    required this.userId,
    required this.author,
    required this.rating,
    required this.body,
    required this.createdAt,
    this.photoPath,
  });

  final int id;
  final int productId;
  final int? userId;
  final String author;
  final int rating;
  final String body;
  final DateTime createdAt;

  /// Photo of the product attached by the author (local file), if any.
  final String? photoPath;

  factory Review.fromMap(Map<String, Object?> m) => Review(
    id: m['id'] as int,
    productId: m['product_id'] as int,
    userId: m['user_id'] as int?,
    author: m['author'] as String,
    rating: m['rating'] as int,
    body: m['body'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    photoPath: m['photo_path'] as String?,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final bool isUser;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromMap(Map<String, Object?> m) => ChatMessage(
    id: m['id'] as int,
    isUser: (m['is_user'] as int) == 1,
    text: m['text'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}
