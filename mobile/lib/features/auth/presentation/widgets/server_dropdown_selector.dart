import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/server_option.dart';
import '../providers/servers_provider.dart';

/// Seletor de servidor do cabeçalho. Lista os servidores disponíveis,
/// destaca o selecionado e termina com a opção de adicionar outro.
class ServerDropdownSelector extends ConsumerWidget {
  const ServerDropdownSelector({super.key, this.onAddServer});

  final VoidCallback? onAddServer;

  static const addLabel = '+ Adicionar servidor...';

  /// Valor interno do item "adicionar", que não é um [ServerOption].
  static const _addValue = Object();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);

    return PopupMenuButton<Object>(
      tooltip: 'Selecionar servidor',
      color: AppColors.surface,
      elevation: 0,
      offset: const Offset(0, 44),
      constraints: const BoxConstraints(minWidth: 240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (value) {
        if (value is ServerOption) {
          ref.read(selectedServerProvider.notifier).select(value);
        } else {
          onAddServer?.call();
        }
      },
      itemBuilder: (_) => [
        for (final server in servers)
          PopupMenuItem<Object>(
            value: server,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: _ServerItem(server: server, selected: server == selected),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<Object>(
          value: _addValue,
          child: Text(addLabel, style: AppText.mono(12, letterSpacing: 0.4)),
        ),
      ],
      child: _SelectorButton(label: selected.name),
    );
  }
}

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.accentBorder,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppText.mono(11, color: AppColors.text, letterSpacing: 1),
            ),
          ),
          const Icon(Icons.expand_more, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _ServerItem extends StatelessWidget {
  const _ServerItem({required this.server, required this.selected});

  final ServerOption server;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('server-item-${server.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.accentBorder : Colors.transparent,
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
                    color: selected ? AppColors.accentBorder : AppColors.text,
                  ),
                ),
                Text(
                  server.address,
                  style: AppText.mono(11, letterSpacing: 0.4),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check, size: 18, color: AppColors.accentBorder),
        ],
      ),
    );
  }
}
