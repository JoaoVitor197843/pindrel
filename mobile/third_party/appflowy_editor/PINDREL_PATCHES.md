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

3. Tables (see `lib/src/editor/block_component/table_block_component/`):
   - new `table_rows_view.dart` and `table_lazy_rows.dart`; `TableBlockComponentBuilder(byRows: true)` lays the table out
     by rows and builds only the rows near the screen; the stock column layout is kept for the memory comparison only.
   - `TableNode` and the builder's `validate` read the cells in one pass (they searched all of them for every position).
   - `TableActions.clear` (row and column) removes the old paragraph instead of leaving it under the new one.
   - `table.dart` exports `LazyRows`, `RowsTableView`, `TableOps`, `TableMenuItem` and `TableLabels`.
4. `desktop_selection_service.dart`: the context menu also opens for a caret (it needed a selection with rectangles).

Only `lib/` and `assets/` were copied (no tests, no example).

- `pubspec.yaml`: `keyboard_height_plugin` ^0.1.5 -> ^0.3.0. 0.1.5 compiles against android-31 and the AndroidX libraries it pulls in need 34+, so `checkReleaseAarMetadata` failed the Android release build (v0.1.0-alpha.10). The API we use (`onKeyboardHeightChanged`, `dispose`) is unchanged.
