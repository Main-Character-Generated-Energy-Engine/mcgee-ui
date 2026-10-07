import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _userAgent;

@JS('navigator.onLine')
external bool get _online;

List<String> browserDetails() => [
  'Browser: $_userAgent',
  'Browser network status: ${_online ? 'online' : 'offline'}',
  'Site: ${Uri.base.origin}',
];
