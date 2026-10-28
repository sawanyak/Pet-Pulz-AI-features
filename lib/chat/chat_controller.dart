import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pet_core/pet_core.dart';
import '../profile/cat_profile_store.dart';
import 'chat_history.dart';

/// Holds the chat's *state* and the logic that changes it.
///
/// Flutter pattern: [ChangeNotifier] keeps a list of listeners (our screen).
/// Whenever we call [notifyListeners], the screen rebuilds itself with the
/// latest data. The UI never modifies messages directly; it asks the
/// controller to. This separation ("state vs. view") keeps code testable.
class ChatController extends ChangeNotifier {
  /// If a [history] is given, the conversation is loaded from it now and
  /// saved back after every change.
  ///
  /// If a [store] is given, SEVERAL chats are saved and [history] is ignored.
  ChatController(
    this._ai,
    this._profiles, {
    ChatHistory? history,
    ChatStore? store,
  }) : _history = store == null ? history : null,
       _store = store {
    if (store != null) {
      _sessions.addAll(store.load());
      _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else if (history != null) {
      _sessions.add(_newSession()..messages.addAll(history.load()));
    }
    if (_sessions.isEmpty) _sessions.add(_newSession());
    _active = _sessions.first;
  }

  final AiService _ai;
  final CatProfileStore _profiles;
  final ChatHistory? _history;
  final ChatStore? _store;

  /// Every chat; the one on screen is [_active]. Its message list IS
  /// [_messages], so the rest of this class works on "the chat" as before.
  final List<ChatSession> _sessions = [];
  late ChatSession _active;
  int _idCounter = 0;

  List<ChatMessage> get _messages => _active.messages;

  ChatSession _newSession() => ChatSession(
    id: '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
  );

  /// Cancels the reply that is currently being read, if any.
  void Function()? _cancelActive;

  /// Waiting for the FIRST piece of the reply (shows the typing dots).
  bool _isThinking = false;

  /// The reply is arriving piece by piece (the bubble is growing).
  bool _isStreaming = false;

  /// Bumped by [clear]. A running [send] compares it with the value it
  /// started with, so a reply that arrives after "New chat" is ignored
  /// instead of appearing in the fresh conversation.
  int _generation = 0;

  /// Read-only view so outside code can't mutate our list by accident.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// All chats, newest first (the active one is always included).
  List<ChatSession> get sessions =>
      List.unmodifiable(
        [..._sessions]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );

  String get activeChatId => _active.id;

  bool get isThinking => _isThinking;
  bool get isStreaming => _isStreaming;

  /// True from the moment the user sends until the reply is finished.
  bool get isBusy => _isThinking || _isStreaming;

  /// Called when the user taps send (or a suggestion chip).
  ///
  /// [spoken] is true in voice mode: the AI is then asked for short replies
  /// without formatting, because the answer will be read aloud.
  Future<void> send(String rawText, {bool spoken = false}) async {
    final text = rawText.trim();
    if (text.isEmpty || isBusy) return; // ignore blanks & double-taps

    final generation = _generation;

    // 1. Show the user's message immediately (feels instant).
    _messages.add(
      ChatMessage(role: ChatRole.user, text: text, timestamp: DateTime.now()),
    );
    _isThinking = true;
    notifyListeners();
    _persist(); // so the question survives even if the app is closed now

    // 2. Read the reply piece by piece.
    //
    // We hold on to the stream SUBSCRIPTION (instead of a plain `await for`)
    // so that stopReply() / clear() can cancel it at once. Cancelling closes
    // the connection to the AI immediately; with `await for` the loop would
    // only notice it had been told to stop when the next chunk arrived.
    final buffer = StringBuffer();
    int? replyIndex; // where the growing assistant bubble lives in the list
    final finished = Completer<void>();
    Object? failure;
    StreamSubscription<String>? subscription;

    void onPiece(String piece) {
      if (generation != _generation) return; // stopped: ignore stragglers

      buffer.write(piece);
      final soFar = buffer.toString().trimLeft();
      if (soFar.isEmpty) return; // don't show an empty bubble

      // ChatMessage is immutable, so to "grow" the bubble we replace it
      // with a new message holding the longer text.
      final message = ChatMessage(
        role: ChatRole.assistant,
        text: soFar,
        timestamp: DateTime.now(),
      );
      if (replyIndex == null) {
        _messages.add(message);
        replyIndex = _messages.length - 1;
        _isThinking = false; // first words arrived: dots -> real bubble
        _isStreaming = true;
      } else {
        _messages[replyIndex!] = message;
      }
      notifyListeners();
    }

    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    try {
      // The system prompt is rebuilt on EVERY request, so editing the cat's
      // profile takes effect on the very next message. The AI is sent only
      // the recent part of the conversation (see contextWindow).
      final stream = _ai.replyStream(
        contextWindow(_messages),
        cat: _profiles.profile,
        spoken: spoken,
      );
      subscription = stream.listen(
        onPiece,
        onError: (Object e) {
          failure = e;
          finish();
        },
        onDone: finish,
        cancelOnError: true,
      );
      _cancelActive = () {
        subscription?.cancel();
        finish();
      };

      await finished.future;

      if (generation == _generation && failure != null) {
        final e = failure;
        _addError(
          e is AiServiceException
              ? e.message
              : 'Something unexpected went wrong. Please try again.',
        );
      }
    } catch (_) {
      if (generation == _generation) {
        _addError('Something unexpected went wrong. Please try again.');
      }
    } finally {
      _cancelActive = null;
      // 3. Always leave the busy state, success or failure (unless the chat
      //    was cleared or stopped, in which case that method already reset
      //    everything).
      if (generation == _generation) {
        _isThinking = false;
        _isStreaming = false;
        notifyListeners();
        _persist();
      }
    }
  }

  /// Retry the last question after an error bubble.
  Future<void> retry() async {
    if (_messages.isEmpty || !_messages.last.isError || isBusy) return;
    // Drop the error bubble and any half-finished reply, then the question
    // itself, and resend it cleanly.
    while (_messages.isNotEmpty && !_messages.last.isUser) {
      _messages.removeLast();
    }
    final lastUser = _messages.removeLast().text;
    notifyListeners();
    await send(lastUser);
  }

  /// Stops a reply that is still being written (thinking or streaming).
  /// Whatever text already arrived stays in the chat.
  void stopReply() {
    if (!isBusy) return;
    _generation++; // the running send() must not touch the chat any more
    _cancelActive?.call(); // ...and its connection is closed right away
    _isThinking = false;
    _isStreaming = false;
    notifyListeners();
    _persist(); // keep the part of the reply that arrived
  }

  void clear() {
    _abortReply();
    _messages.clear();
    notifyListeners();
    _forget();
  }

  /// Ends any reply still arriving, without touching the messages.
  void _abortReply() {
    _generation++; // invalidates any reply still streaming in
    _cancelActive?.call();
    _isThinking = false;
    _isStreaming = false;
  }

  /// Starts a fresh chat. The old one stays in the history list.
  void newChat() {
    if (_messages.isEmpty && !isBusy) return; // already a blank chat
    _switchTo(_newSession(), addIfNew: true);
  }

  /// Shows a saved chat.
  void selectChat(String id) {
    if (id == _active.id) return;
    final target = _sessions.where((s) => s.id == id).firstOrNull;
    if (target != null) _switchTo(target);
  }

  /// Removes a chat for good. Deleting the open one opens the newest other
  /// chat, or a blank one if none is left.
  void deleteChat(String id) {
    final target = _sessions.where((s) => s.id == id).firstOrNull;
    if (target == null) return;
    if (target.id == _active.id) {
      _abortReply();
      _sessions.remove(target);
      if (_sessions.isEmpty) _sessions.add(_newSession());
      _active = sessions.first;
    } else {
      _sessions.remove(target);
    }
    notifyListeners();
    _persistAll();
  }

  void _switchTo(ChatSession target, {bool addIfNew = false}) {
    _abortReply();
    final leaving = _active;
    // A chat nobody wrote in is not worth keeping.
    if (leaving.messages.isEmpty) _sessions.remove(leaving);
    if (addIfNew) _sessions.add(target);
    _active = target;
    notifyListeners();
    _persistAll();
  }

  /// Saves the conversation. Fire-and-forget: a storage problem must never
  /// break the chat, so failures are ignored.
  void _persist() {
    _active.updatedAt = DateTime.now();
    _persistAll();
  }

  void _persistAll() {
    final store = _store;
    if (store != null) {
      store.save(List.of(_sessions)).catchError((Object _) {});
      return;
    }
    final history = _history;
    if (history == null) return;
    history.save(List.of(_messages)).catchError((Object _) {});
  }

  void _forget() {
    final store = _store;
    if (store != null) {
      store.save(List.of(_sessions)).catchError((Object _) {});
      return;
    }
    _history?.clear().catchError((Object _) {});
  }

  void _addError(String message) {
    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        text: message,
        timestamp: DateTime.now(),
        isError: true,
      ),
    );
  }
}
