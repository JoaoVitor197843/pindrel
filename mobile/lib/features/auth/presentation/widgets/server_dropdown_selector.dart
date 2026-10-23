import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/server_list_controller.dart';
import '../../data/server_list_state.dart';
import '../../data/server_option.dart';
import '../providers/servers_provider.dart';
import 'pulsing_dot.dart';

/// Cor e animação da bolinha de cada situação do servidor escolhido.
Color connectionColor(ServerConnection connection) => switch (connection) {
  ServerConnection.connected => AppColors.accentBorder,
  ServerConnection.disconnected => AppColors.offline,
  ServerConnection.none => AppColors.textMuted,
};

/// A bolinha é do tamanho de uma letra do texto ao lado.
double dotDiameterFor(double fontSize) => (fontSize * 0.8).roundToDouble();

/// Seletor de servidor do cabeçalho.
///
/// O botão e o menu acompanham a lista ao vivo (`StreamBuilder`), inclusive com
/// o menu aberto. O menu lista os disponíveis, destaca o escolhido e, se o
/// escolhido saiu da rede, mostra-o em "Desconectados"; termina com a opção de
/// adicionar outro. Ao lado esquerdo do nome, uma bolinha pulsante: verde com o
/// servidor na rede, vermelha sem ele.
class ServerDropdownSelector extends ConsumerWidget {
  const ServerDropdownSelector({
    super.key,
    this.onAddServer,
    this.maxWidth = defaultMaxWidth,
  });

  final VoidCallback? onAddServer;

  /// Largura máxima do botão; o nome ganha reticências se não couber.
  final double maxWidth;

  /// Cabeçalho do celular. O desktop passa uma largura maior.
  static const defaultMaxWidth = 156.0;

  static const addLabel = '+ Adicionar servidor...';
  static const searchingLabel = 'Procurando servidores na rede...';
  static const searchFailedLabel = 'Não foi possível procurar na rede.';
  static const availableLabel = 'Disponíveis';
  static const disconnectedLabel = 'Desconectados';

  /// Valor interno do item "adicionar", que não é um [ServerOption].
  static const _addValue = Object();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(serverListControllerProvider);

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
          onSelected: (value) {
            if (value is ServerOption) {
              controller.select(value);
            } else {
              onAddServer?.call();
            }
          },
          // Uma única entrada, com o seu próprio StreamBuilder: os itens de um
          // PopupMenuButton comum são montados só ao abrir.
          itemBuilder: (_) => [
            _ServerMenuEntry(controller: controller, addValue: _addValue),
          ],
          child: _SelectorButton(state: state, maxWidth: maxWidth),
        );
      },
    );
  }
}

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({required this.state, required this.maxWidth});

  final ServerListState state;
  final double maxWidth;

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
              (state.selected?.name ?? 'Buscando').toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppText.mono(
                _fontSize,
                color: AppColors.text,
                letterSpacing: 1,
              ),
            ),
          ),
          const Icon(Icons.expand_more, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// O conteúdo inteiro do menu, atualizado ao vivo.
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
            if (state.available.isEmpty)
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
                onTap: () => Navigator.pop(context, server),
              ),
            if (disconnected.isNotEmpty) ...[
              const _SectionLabel(ServerDropdownSelector.disconnectedLabel),
              for (final server in disconnected)
                _ServerItem(
                  server: server,
                  selected: server == state.selected,
                  connected: false,
                  onTap: () => Navigator.pop(context, server),
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

  /// Falso na seção "Desconectados".
  final bool connected;
  final VoidCallback onTap;

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
