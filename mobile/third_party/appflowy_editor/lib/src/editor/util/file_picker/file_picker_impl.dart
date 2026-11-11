// PINDREL PATCH: the upstream file used the `file_picker` plugin. Pindrel never
// uses this package's image block (files go through its own upload service), and
// the plugin cannot resolve next to flutter_secure_storage 11 (win32 5 vs 6).
// These stand-ins keep the image upload widget compiling; picking returns null.
import 'dart:typed_data';

enum FileType { any, image, custom }

class PlatformFile {
  const PlatformFile({this.path, this.bytes});
  final String? path;
  final Uint8List? bytes;
}

class FilePickerResult {
  const FilePickerResult(this.files);
  final List<PlatformFile> files;
}

class FilePicker {
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool withData = false,
  }) async =>
      null;
}
