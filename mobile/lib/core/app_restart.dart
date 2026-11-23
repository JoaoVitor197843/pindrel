import 'package:flutter/widgets.dart';

/// Rebuilds everything below it from scratch (new provider state, new controllers). Used after the device's data is
/// erased, so nothing in memory writes it back.
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.child});
  final Widget child;

  /// False when there is no [AppRestart] above (tests).
  static bool restart(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_RestartScope>();
    scope?.state._restart();
    return scope != null;
  }

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  Key _key = UniqueKey();

  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) => _RestartScope(state: this, child: KeyedSubtree(key: _key, child: widget.child));
}

class _RestartScope extends InheritedWidget {
  const _RestartScope({required this.state, required super.child});
  final _AppRestartState state;

  @override
  bool updateShouldNotify(_RestartScope old) => false;
}
