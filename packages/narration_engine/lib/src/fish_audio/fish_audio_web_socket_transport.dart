import 'dart:typed_data';

/// The small WebSocket surface needed by the Fish Audio live TTS adapter.
///
/// Keeping this boundary provider-neutral makes the protocol testable without
/// opening a network connection, and allows a host-side relay transport to be
/// supplied by Flutter web applications.
abstract interface class FishAudioWebSocket {
  Stream<Uint8List> get messages;

  void send(Uint8List message);

  Future<void> close();
}

abstract interface class FishAudioWebSocketTransport {
  Future<FishAudioWebSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  });
}
