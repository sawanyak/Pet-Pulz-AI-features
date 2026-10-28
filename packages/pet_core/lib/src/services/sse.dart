import 'dart:convert';

/// Turns a raw HTTP byte stream into the payloads of Server-Sent Events.
///
/// Built from stream TRANSFORMERS rather than an `async*` generator on
/// purpose: cancelling a transformer chain immediately cancels the network
/// connection underneath it, whereas a generator that is waiting for the
/// next chunk cannot be cancelled until that chunk arrives.
///
/// WHAT IS SSE? When you ask an AI API to "stream", it keeps the connection
/// open and sends text lines as it generates, like:
///
///   data: {"...first few words..."}
///
///   data: {"...next few words..."}
///
/// This helper does three jobs:
///   1. decode bytes to text (`utf8.decoder` correctly handles emoji that
///      get split across two network packets),
///   2. split the text into lines,
///   3. keep only the `data:` lines and yield what follows the colon.
Stream<String> sseData(Stream<List<int>> bytes) => bytes
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .where(
      (line) => line.startsWith('data:'),
    ) // skip "event:", comments, blanks
    .map((line) => line.substring(5).trim())
    .where((payload) => payload.isNotEmpty);
