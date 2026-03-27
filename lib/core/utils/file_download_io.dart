import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<bool> saveTextFile({
  required String fileName,
  required String content,
  String? dialogTitle,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle ?? 'Guardar archivo',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
  if (path == null || path.trim().isEmpty) {
    return false;
  }

  await File(path).writeAsString(content);
  return true;
}