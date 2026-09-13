import 'dart:io';
import 'dart:typed_data';

import 'fish_audio_web_socket_transport.dart';

/// A Fish Audio WebSocket transport for mobile, desktop, and command-line
/// Dart hosts.
///
/// This deliberately lives in `fish_audio_io.dart`: browser WebSocket APIs do
/// not allow the required `Authorization` and `model` handshake headers.
final class IoFishAudioWebSocketTransport
    implements FishAudioWebSocketTransport {
  const IoFishAudioWebSocketTransport();

  @override
  Future<FishAudioWebSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final socket = await WebSocket.connect(uri.toString(), headers: headers);
    return _IoFishAudioWebSocket(socket);
  }
}

final class _IoFishAudioWebSocket implements FishAudioWebSocket {
  _IoFishAudioWebSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Uint8List> get messages => _socket.map((message) {
    if (message is Uint8List) {
      return message;
    }
    if (message is List<int>) {
      return Uint8List.fromList(message);
    }
    throw const FormatException(
      'Fish Audio sent a text WebSocket frame; MessagePack binary was expected',
    );
  });

  @override
  void send(Uint8List message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}
