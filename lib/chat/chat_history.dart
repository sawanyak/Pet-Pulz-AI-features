import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_core/pet_core.dart';

/// Where the conversation is remembered between app launches.
///
/// An interface, like the other services, so the controller doesn't care
/// whether it is stored in shared_preferences, a database, or nowhere.
abstract class ChatHistory {
  List<ChatMessage> load();
  Future<void> save(List<ChatMessage> messages);
  Future<void> clear();
}

/// Keeps the chat on the phone using `shared_preferences`, as one JSON list.
///
/// PRIVACY: it never leaves the device. (It is only sent to the AI service,
/// as the last few messages, when you ask something.)
class PrefsChatHistory implements ChatHistory {
  PrefsChatHistory(this._prefs);

  static const _key = 'chat_history_v1';

  /// Older messages are dropped when saving, so storage stays small.
  static const maxSaved = 200;

  final SharedPreferences _prefs;

  static Future<PrefsChatHistory> open() async =>
      PrefsChatHistory(await SharedPreferences.getInstance());

  @override
  List<ChatMessage> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final item in list) ?ChatMessage.tryFromJson(item)];
    } catch (_) {
      // Damaged data must never stop the app from starting.
      return const [];
    }
  }

  @override
  Future<void> save(List<ChatMessage> messages) {
    // Error bubbles are notices ("no internet"), not conversation.
    final keep = messages.where((m) => !m.isError).toList();
    final recent = keep.length > maxSaved
        ? keep.sublist(keep.length - maxSaved)
        : keep;
    return _prefs.setString(
      _key,
      jsonEncode([for (final m in recent) m.toJson()]),
    );
  }

  @override
  Future<void> clear() => _prefs.remove(_key);
}

/// One saved conversation in the chat history list.
class ChatSession {
  ChatSession({
    required this.id,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  }) : messages = messages ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String id;

  /// Mutable on purpose: the controller edits the active chat's list directly.
  final List<ChatMessage> messages;
  DateTime updatedAt;

  /// Named after the first question, like most chat apps do.
  String get title {
    for (final m in messages) {
      if (m.isUser) {
        final text = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) break;
        return text.length > 40 ? '${text.substring(0, 40)}...' : text;
      }
    }
    return 'New chat';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': [
      for (final m in messages)
        if (!m.isError) m.toJson(),
    ],
  };

  static ChatSession? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final rawMessages = json['messages'];
    if (id is! String || rawMessages is! List) return null;
    return ChatSession(
      id: id,
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
      messages: [for (final item in rawMessages) ?ChatMessage.tryFromJson(item)],
    );
  }
}

/// Where ALL the saved chats are remembered between app launches.
abstract class ChatStore {
  List<ChatSession> load();
  Future<void> save(List<ChatSession> sessions);
}

/// Keeps several chats on the phone using `shared_preferences`.
///
/// An older single-chat save (see [PrefsChatHistory]) is picked up as the
/// first chat, so nobody loses their conversation after updating.
class PrefsChatStore implements ChatStore {
  PrefsChatStore(this._prefs);

  static const _key = 'chat_sessions_v1';

  /// Per-chat and total limits keep storage small.
  static const maxMessagesPerChat = 200;
  static const maxChats = 50;

  final SharedPreferences _prefs;

  static Future<PrefsChatStore> open() async =>
      PrefsChatStore(await SharedPreferences.getInstance());

  @override
  List<ChatSession> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) {
      final legacy = PrefsChatHistory(_prefs).load();
      if (legacy.isEmpty) return [];
      return [ChatSession(id: 'legacy', messages: [...legacy])];
    }
    try {
      final list = jsonDecode(raw) as List;
      return [for (final item in list) ?ChatSession.tryFromJson(item)];
    } catch (_) {
      // Damaged data must never stop the app from starting.
      return [];
    }
  }

  @override
  Future<void> save(List<ChatSession> sessions) {
    final keep = sessions.where((s) => s.messages.any((m) => !m.isError)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recent = keep.length > maxChats ? keep.sublist(0, maxChats) : keep;
    final encoded = [
      for (final s in recent)
        ChatSession(
          id: s.id,
          updatedAt: s.updatedAt,
          messages: s.messages.length > maxMessagesPerChat
              ? s.messages.sublist(s.messages.length - maxMessagesPerChat)
              : s.messages,
        ).toJson(),
    ];
    return _prefs.setString(_key, jsonEncode(encoded));
  }
}

/// The part of the conversation that is sent to the AI with a question.
///
/// The AI has no memory, so it is sent the recent history each time. A long
/// saved chat would make every request slower and more expensive (and can
/// hit the AI's size limit), so only the last [max] messages go. The window
/// always STARTS with a user message, because Claude rejects a conversation
/// that begins with the assistant.
List<ChatMessage> contextWindow(List<ChatMessage> messages, {int max = 30}) {
  final real = messages.where((m) => !m.isError).toList();
  var window = real.length > max ? real.sublist(real.length - max) : real;
  final firstUser = window.indexWhere((m) => m.isUser);
  if (firstUser > 0) window = window.sublist(firstUser);
  return window;
}
