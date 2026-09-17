import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readCapturePath(String path) => File(path).readAsBytes();
