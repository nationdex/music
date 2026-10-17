/// System file pickers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../state/library_controller.dart';

const audioExtensions = ['mp3', 'm4a', 'm4b', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav', 'webm', 'mp4', 'aif', 'aiff', 'ape'];

/// Lets the user pick audio files from the system Files app / document picker.
Future<List<ImportSource>> pickAudioFiles() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: audioExtensions);
  return [
    for (final f in files)
      if (f.path != null) ImportSource(path: f.path!, name: f.name),
  ];
}

/// Lets the user pick a backup `.json` and returns its text, or null if cancelled.
Future<String?> pickBackupFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
  if (file == null || file.path == null) return null;
  return utf8.decode(await File(file.path!).readAsBytes());
}
