class ChatMessage {
  final String id;
  final String text;
  final String senderEmail;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderEmail,
    required this.timestamp,
  });

  factory ChatMessage.fromFirestore(Map<String, dynamic> data, String id) {
    return ChatMessage(
      id: id,
      text: data['text'] ?? '',
      senderEmail: data['email'] ?? 'unknown',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}