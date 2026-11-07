import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'ui.dart';

/// Search, the quick-search button and the account chip. Phones get the menu button in front.
class NotesTopBar extends StatelessWidget {
  const NotesTopBar({
    super.key,
    required this.search,
    required this.onQuery,
    required this.compact,
    required this.showMenuButton,
    required this.userName,
    required this.server,
    required this.onMenu,
    required this.onPalette,
    required this.onSettings,
    required this.onData,
    required this.onAccount,
  });

  final TextEditingController search;
  final ValueChanged<String> onQuery;
  final bool compact, showMenuButton;
  final String userName, server;
  final VoidCallback onMenu, onPalette, onSettings, onData, onAccount;

  String get _initials {
    final words = userName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2);
    final s = words.map((w) => w[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 768;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 32 : 16,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            OutlineIconButton(
              icon: Icons.menu,
              tooltip: 'Abrir menu',
              onPressed: onMenu,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 576),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: search,
                    onChanged: onQuery,
                    maxLength: 200,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: compact
                          ? 'Buscar…'
                          : 'Buscar em todas as páginas…',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.search,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: search,
                        builder: (_, v, _) => v.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: 'Limpar busca',
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  search.clear();
                                  onQuery('');
                                },
                              ),
                      ),
                      contentPadding: const EdgeInsets.only(right: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(fieldRadius),
                        borderSide: const BorderSide(
                          color: AppColors.fieldBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(fieldRadius),
                        borderSide: const BorderSide(
                          color: AppColors.accentBorder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Busca rápida',
            child: Semantics(
              button: true,
              label: 'Abrir busca rápida',
              child: RingInkWell(
                borderRadius: BorderRadius.circular(fieldRadius),
                onTap: onPalette,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        Text(
                          defaultTargetPlatform == TargetPlatform.macOS
                              ? '⌘K'
                              : 'Ctrl K',
                          style: AppText.mono(12, letterSpacing: 0),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Menu da conta de $userName',
            color: AppColors.surface,
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              side: const BorderSide(color: AppColors.border),
            ),
            onSelected: (run) => run(),
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                    Text(server, style: AppText.mono(12, letterSpacing: 0)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: onSettings,
                child: const Text(
                  'Configurações',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              PopupMenuItem(
                value: onData,
                child: const Text(
                  'Importar / exportar',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: onAccount,
                child: const Text(
                  'Conta e servidor',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fieldRadius),
                border: Border.all(
                  color: desktop ? AppColors.border : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _initials,
                      style: AppText.mono(
                        14,
                        color: AppColors.text,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (!compact && MediaQuery.sizeOf(context).width >= 1024) ...[
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(server, style: AppText.mono(12, letterSpacing: 0)),
                      ],
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
