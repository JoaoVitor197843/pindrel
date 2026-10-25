import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/server_list_controller.dart';
import '../../data/server_list_state.dart';
import '../../data/server_option.dart';
import '../providers/servers_provider.dart';
import 'pulsing_dot.dart';
import 'skeleton_bar.dart';

/// Color and animation of the dot for each situation of the chosen server.
Color connectionColor(ServerConnection connection) => switch (connection) {
  ServerConnection.connected => AppColors.accentBorder,
  ServerConnection.disconnected => AppColors.offline,
  ServerConnection.none => AppColors.textMuted,
};

/// The dot is the size of a letter of the text beside it.
double dotDiameterFor(double fontSize) => (fontSize * 0.8).roundToDouble();

/// Server selector in the header.
///
/// The button and the menu follow the live list (`StreamBuilder`), even with
/// the menu open. The menu lists the available ones, highlights the chosen one and, if the
/// chosen one left the network, shows it under "Desconectados"; it ends with the option to
/// add another. To the left of the name, a pulsing dot: green with the
/// server on the network, red without it.
class ServerDropdownSelector extends ConsumerStatefulWidget {
  const ServerDropdownSelector({
    super.key,
    this.onAddServer,
    this.maxWidth = defaultMaxWidth,
  });

  final VoidCallback? onAddServer;

  /// Maximum width of the button; the name gets an ellipsis if it does not fit.
  final double maxWidth;

  /// Mobile header. Desktop passes a larger width.
  static const defaultMaxWidth = 156.0;

  static const addLabel = '+ Adicionar servidor...';
  static const searchingLabel = 'Procurando servidores na rede...';
  static const searchFailedLabel = 'Não foi possível procurar na rede.';
  static const availableLabel = 'Disponíveis';
  static const disconnectedLabel = 'Desconectados';

  /// Internal value of the "add" item, which is not a [ServerOption].
  static const _addValue = Object();

  @override
  ConsumerState<ServerDropdownSelector> createState() =>
      _ServerDropdownSelectorState();
}

class _ServerDropdownSelectorState
    extends ConsumerState<ServerDropdownSelector> {
  /// Menu open: the button's arrow turns.
  bool _open = false;

  StreamSubscription<ServerListState>? _changes;
  ServerListController? _watched;
  bool _asking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ref.read(serverListControllerProvider);
    if (identical(controller, _watched)) return;
    _changes?.cancel();
    _watched = controller;
    _changes = controller.stream.listen((state) {
      final pending = state.pendingChange;
      if (pending != null && !_asking && mounted) _ask(controller, pending);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  /// The name is one the user opened before but the server answering now has another id: asks before going on.
  Future<void> _ask(
    ServerListController controller,
    ServerOption server,
  ) async {
    _asking = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangedServerDialog(name: server.name),
    );
    _asking = false;
    if (go == true) {
      if (!await controller.confirmChange()) {
        messenger?.showSnackBar(
          SnackBar(content: Text('${server.name} não respondeu.')),
        );
      }
    } else {
      controller.cancelChange();
    }
  }

  void _setOpen(bool open) {
    if (mounted && _open != open) setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(serverListControllerProvider);
    final onAddServer = widget.onAddServer;

    return StreamBuilder<ServerListState>(
      initialData: controller.current,
      stream: controller.stream,
      builder: (context, snapshot) {
        final state = snapshot.requireData;
        return PopupMenuButton<Object>(
          tooltip: 'Selecionar servidor',
          color: AppColors.surface,
          elevation: 0,
          offset: const Offset(0, 44),
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: const BorderSide(color: AppColors.border),
          ),
          onOpened: () => _setOpen(true),
          onCanceled: () => _setOpen(false),
          onSelected: (value) async {
            _setOpen(false);
            if (value is ServerOption) {
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (!await controller.select(value)) {
                messenger?.showSnackBar(
                  SnackBar(content: Text('${value.name} não respondeu.')),
                );
              }
            } else {
              onAddServer?.call();
            }
          },
          // A single entry, with its own StreamBuilder: the items of an ordinary
          // PopupMenuButton are only built on open.
          itemBuilder: (_) => [
            _ServerMenuEntry(
              controller: controller,
              addValue: ServerDropdownSelector._addValue,
            ),
          ],
          child: _SelectorButton(
            state: state,
            maxWidth: widget.maxWidth,
            open: _open,
          ),
        );
      },
    );
  }
}

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.state,
    required this.maxWidth,
    required this.open,
  });

  final ServerListState state;
  final double maxWidth;
  final bool open;

  static const _fontSize = 11.0;

  @override
  Widget build(BuildContext context) {
    final connection = state.connection;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: switch (connection) {
              ServerConnection.connected => 'Servidor conectado',
              ServerConnection.disconnected => 'Servidor desconectado',
              ServerConnection.none => 'Nenhum servidor',
            },
            child: PulsingDot(
              key: const ValueKey('server-status-dot'),
              color: connectionColor(connection),
              diameter: dotDiameterFor(_fontSize),
              pulsing: connection != ServerConnection.none,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              (state.connecting != null
                      ? 'Abrindo ${state.connecting!.name}…'
                      : state.selected?.name ?? 'Buscando')
                  .toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppText.mono(
                _fontSize,
                color: AppColors.text,
                letterSpacing: 1,
              ),
            ),
          ),
          AnimatedRotation(
            key: const ValueKey('server-chevron'),
            turns: open ? 0.5 : 0,
            duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? Duration.zero
                : const Duration(milliseconds: 200),
            child: const Icon(
              Icons.expand_more,
              size: 16,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole content of the menu, updated live.
class _ServerMenuEntry extends PopupMenuEntry<Object> {
  const _ServerMenuEntry({required this.controller, required this.addValue});

  final ServerListController controller;
  final Object addValue;

  @override
  double get height => 48;

  @override
  bool represents(Object? value) => false;

  @override
  State<_ServerMenuEntry> createState() => _ServerMenuEntryState();
}

class _ServerMenuEntryState extends State<_ServerMenuEntry> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerListState>(
      initialData: widget.controller.current,
      stream: widget.controller.stream,
      builder: (context, snapshot) {
        final state = snapshot.requireData;
        final disconnected = state.disconnected;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (disconnected.isNotEmpty)
              const _SectionLabel(ServerDropdownSelector.availableLabel),
            if (!state.loaded)
              const _ServersSkeleton()
            else if (state.available.isEmpty)
              _Hint(
                state.searchError != null
                    ? ServerDropdownSelector.searchFailedLabel
                    : ServerDropdownSelector.searchingLabel,
              ),
            for (final server in state.available)
              _ServerItem(
                server: server,
                selected: server == state.selected,
                connected: true,
                onTap: state.connecting != null
                    ? null
                    : () => Navigator.pop(context, server),
              ),
            if (disconnected.isNotEmpty) ...[
              const _SectionLabel(ServerDropdownSelector.disconnectedLabel),
              for (final server in disconnected)
                _ServerItem(
                  server: server,
                  selected: server == state.selected,
                  connected: false,
                  onTap: state.connecting != null
                      ? null
                      : () => Navigator.pop(context, server),
                ),
            ],
            const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: () => Navigator.pop(context, widget.addValue),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text(
                  ServerDropdownSelector.addLabel,
                  style: AppText.mono(12, letterSpacing: 0.4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: AppText.mono(10, letterSpacing: 1.4),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(text, style: AppText.mono(12, letterSpacing: 0.4)),
    );
  }
}

class _ServerItem extends StatelessWidget {
  const _ServerItem({
    required this.server,
    required this.selected,
    required this.connected,
    required this.onTap,
  });

  final ServerOption server;
  final bool selected;

  /// False in the "Desconectados" section.
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = connected ? AppColors.accentBorder : AppColors.offline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          key: ValueKey('server-item-${server.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (connected
                      ? AppColors.accentSoft
                      : AppColors.offline.withValues(alpha: 0.15))
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? highlight : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: !connected
                            ? AppColors.textMuted
                            : selected
                            ? AppColors.accentBorder
                            : AppColors.text,
                      ),
                    ),
                    Text(
                      server.address,
                      style: AppText.mono(11, letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check, size: 18, color: highlight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two ghost items while the search's first answer has not arrived.
class _ServersSkeleton extends StatelessWidget {
  const _ServersSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('servers-skeleton'),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          SkeletonBar(height: 36),
          SizedBox(height: 8),
          SkeletonBar(height: 36),
        ],
      ),
    );
  }
}

/// Asks whether to go on to a server that is not the one opened before under that name. The safe answer has the focus.
class _ChangedServerDialog extends StatelessWidget {
  const _ChangedServerDialog({required this.name});

  final String name;

  static const title = 'Este servidor mudou';
  static const cancelLabel = 'Cancelar';
  static const continueLabel = 'Continuar mesmo assim';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text(
        title,
        style: TextStyle(fontFamily: 'serif', color: AppColors.text),
      ),
      content: Text(
        'O que responde como “$name” não é o mesmo servidor que você abriu '
        'antes. Pode ser um servidor novo com o mesmo nome, ou outro aparelho '
        'da rede se passando por ele. Só continue se você o reconhece: ele '
        'verá a senha que você digitar.',
        style: const TextStyle(color: AppColors.textMuted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            continueLabel,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryButton,
            foregroundColor: AppColors.onPrimaryButton,
          ),
          child: const Text(cancelLabel),
        ),
      ],
    );
  }
}
