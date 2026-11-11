# Local copy of appflowy_editor

Upstream: https://github.com/AppFlowy-IO/appflowy-editor at commit
`01eccc6ee36bd07698bd80915289fe7070478cd2` (main, 2026-08). Dual licensed AGPL-3.0 / MPL-2.0
(see LICENSE); Pindrel uses it under the AGPL-3.0.

Why a copy and not a dependency on pub.dev or git:
- pub.dev 6.2.0 does not compile on Flutter 3.44 (`TextInputClient.onFocusReceived`); the fix is only on main.
- the `file_picker` it depends on needs `win32` ^5, `flutter_secure_storage` 11 needs `win32` ^6.

Changes (search for `PINDREL PATCH`):
1. `lib/src/editor/util/file_picker/` replaced by small stand-ins (no plugin). The image upload
   dialog of the package is not used by Pindrel.
2. `pubspec.yaml`: `file_picker` and the dev dependencies removed.

Only `lib/` and `assets/` were copied (no tests, no example).
