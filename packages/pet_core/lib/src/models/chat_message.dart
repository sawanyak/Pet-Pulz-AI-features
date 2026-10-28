/// Who wrote a message. The Claude API only understands `user` and
/// `assistant`, so we keep the same two roles.
enum ChatRole { user, assistant }

/// One bubble in the conversation.
///
/// This is an immutable "data class": once created it never changes.
/// Immutable data makes UI bugs much rarer, because the screen can only
/// change when we deliberately swap in a new message.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.isError = false,
  });

  final ChatRole role;
  final String text;
  final DateTime timestamp;

  /// True when this bubble represents a failure (network down, bad key...).
  /// Error bubbles are shown in the UI but NOT sent back to the AI.
  final bool isError;

  bool get isUser => role == ChatRole.user;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'time': timestamp.toIso8601String(),
    'error': isError,
  };

  /// Returns null for an entry that can't be understood, so one damaged
  /// message never prevents the rest of the history from loading.
  static ChatMessage? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final time = DateTime.tryParse('${raw['time']}');
    final role = ChatRole.values.where((r) => r.name == raw['role']);
    if (text is! String || text.isEmpty || time == null || role.isEmpty) {
      return null;
    }
    return ChatMessage(
      role: role.first,
      text: text,
      timestamp: time,
      isError: raw['error'] == true,
    );
  }
}
