import 'package:flutter/material.dart';

import '../../../../core/performance/frame_pacer.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/ai_providers.dart';
import '../../data/transfer.dart';
import '../../data/workspace.dart';
import 'ui.dart';

enum _Unsaved { keep, discard, save }

enum SettingsSection { general, power, account, trash, data, ai }

const _nav = {
  SettingsSection.general: 'Geral',
  SettingsSection.power: 'Energia',
  SettingsSection.account: 'Conta',
  SettingsSection.trash: 'Lixeira',
  SettingsSection.data: 'Importar/Exportar',
  SettingsSection.ai: 'IA (opcional)',
};

/// The settings in sections: a list on the left on wide screens, two steps of one screen on a phone.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.ws,
    this.section = SettingsSection.general,
    required this.userName,
    required this.server,
    required this.onAccount,
    required this.onToast,
    this.email,
    this.onLogout,
  });
  final String? email;
  final VoidCallback? onLogout;
  final Workspace ws;
  final SettingsSection section;
  final String userName, server;
  final VoidCallback onAccount;
  final void Function(String message) onToast;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.section;
  late bool _atList = false;
  late bool _useTrash = widget.ws.settings.useTrash;
  late double _days = widget.ws.settings.retention.toDouble();
  late PowerMode _power = widget.ws.settings.power;
  var _provider = aiProviders.first;

  /// Whether the switch or the slider differ from what is saved: the only settings there are to save.
  bool get _dirty =>
      _useTrash != widget.ws.settings.useTrash ||
      _power != widget.ws.settings.power ||
      _days.round() != widget.ws.settings.retention;

  void _save() {
    widget.ws.saveSettings(
      // copy: what this dialog does not show (the text size) must stay as it is
      widget.ws.settings.copy(useTrash: _useTrash, retention: _days.round(), power: _power),
    );
    widget.onToast('Configurações salvas');
    Navigator.pop(context);
  }

  /// Closes the dialog; with unsaved changes it asks first.
  Future<void> _close() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final choice = await showDialog<_Unsaved>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Há alterações não salvas', style: AppText.serif(20)),
        content: const Text('Se fechar agora, elas serão perdidas.'),
        actions: [
          TextButton(
            key: const Key('unsaved-keep'),
            onPressed: () => Navigator.pop(c, _Unsaved.keep),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            key: const Key('unsaved-discard'),
            onPressed: () => Navigator.pop(c, _Unsaved.discard),
            child: const Text(
              'Descartar',
              style: TextStyle(color: AppColors.offlineText),
            ),
          ),
          FilledButton(
            key: const Key('unsaved-save'),
            onPressed: () => Navigator.pop(c, _Unsaved.save),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _Unsaved.save:
        _save();
      case _Unsaved.discard:
        Navigator.pop(context);
      case _Unsaved.keep || null:
        break;
    }
  }

  Future<void> _copyAll(String what) async {
    final ws = widget.ws;
    final pages = exportable(ws.pages);
    for (final p in pages) {
      ws.contentOf(p.id);
    }
    final text = what == 'json'
        ? '[${pages.map((p) => pageToJson(p, ws.tags)).join(',\n')}]'
        : pages.map((p) => pageToMarkdown(p, ws.tags)).join('\n\n---\n\n');
    for (final p in pages) {
      ws.release(p.id);
    }
    await Clipboard.setData(ClipboardData(text: text));
    widget.onToast(
      pages.isEmpty
          ? 'Nada para exportar'
          : 'Copiado: ${pages.length} ${pages.length == 1 ? 'página' : 'páginas'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.sizeOf(context).width < 640;
    final title = stacked && !_atList ? _nav[_section]! : 'Configurações';
    return PopScope(
      // the barrier, the back gesture and the system's back key come here too
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (stacked && !_atList)
                      GhostIconButton(
                        icon: Icons.chevron_left,
                        tooltip: 'Voltar para as seções',
                        iconSize: 18,
                        onPressed: () => setState(() => _atList = true),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(title, style: AppText.serif(20)),
                      ),
                    ),
                    GhostIconButton(
                      icon: Icons.close,
                      tooltip: 'Fechar configurações',
                      iconSize: 18,
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: stacked
                    ? (_atList ? _list(stacked) : _content())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 192,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(
                                  alpha: 0.4,
                                ),
                                border: const Border(
                                  right: BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: _list(stacked),
                            ),
                          ),
                          Expanded(child: _content()),
                        ],
                      ),
              ),
              if (!(stacked && _atList))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlineTextButton(label: 'Cancelar', onPressed: _close),
                      const SizedBox(width: 8),
                      CreamButton(
                        key: const Key('settings-save'),
                        label: 'Salvar',
                        height: 40,
                        onPressed: _dirty ? _save : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(bool stacked) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(8),
    children: [
      for (final e in _nav.entries)
        Material(
          color: !stacked && _section == e.key
              ? AppColors.accent.withValues(alpha: 0.45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(fieldRadius),
          child: RingInkWell(
            borderRadius: BorderRadius.circular(fieldRadius),
            onTap: () => setState(() {
              _section = e.key;
              _atList = false;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 15,
                  color: !stacked && _section == e.key
                      ? AppColors.accentText
                      : AppColors.text,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  static const _powerOptions = <(PowerMode, String, String)>[
    (PowerMode.auto, 'Automático', 'Usa o ritmo máximo da tela (60 ou 120 quadros). Se o aparelho não der conta, passa sozinho para 30 firmes e tenta voltar depois.'),
    (PowerMode.smooth, 'Sempre fluido', 'Nunca limita os quadros, mesmo que o aparelho esteja engasgando. Mais suave, mas gasta mais bateria.'),
    (PowerMode.saving, 'Economia de energia', 'Sempre 30 quadros por segundo, sem animações de enfeite, e tabelas longas ficam mais simples enquanto rolam. A rolagem fica menos fluida.'),
  ];

  Widget _switchRow(Key key, String label, bool on, VoidCallback onTap) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
      Semantics(
        toggled: on,
        label: label,
        child: RingInkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            key: key,
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(2),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? AppColors.accent : AppColors.background,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _content() => ListView(
    padding: const EdgeInsets.all(20),
    shrinkWrap: true,
    children: switch (_section) {
      SettingsSection.general => [
        Text('Geral', style: AppText.serif(24)),
        const SizedBox(height: 16),
        _switchRow(const Key('trash-switch'), 'Usar a lixeira', _useTrash, () => setState(() => _useTrash = !_useTrash)),
        const SizedBox(height: 4),
        Text(
          _useTrash
              ? 'Páginas excluídas ficam guardadas por um tempo.'
              : 'Páginas excluídas somem na hora.',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        Opacity(
          opacity: _useTrash ? 1 : 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dias de retenção da lixeira',
                style: TextStyle(fontSize: 15),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: 7,
                      max: 90,
                      divisions: 83,
                      value: _days,
                      onChanged: _useTrash
                          ? (v) => setState(() => _days = v)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${_days.round()} dias',
                      textAlign: TextAlign.right,
                      style: AppText.mono(12, letterSpacing: 0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      SettingsSection.power => [
        Text('Energia', style: AppText.serif(24)),
        const SizedBox(height: 8),
        const Text(
          'Quantos quadros por segundo o app desenha. Menos quadros gastam menos bateria e esquentam menos o aparelho.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        for (final (mode, title, body) in _powerOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              inMutuallyExclusiveGroup: true,
              checked: _power == mode,
              label: title,
              child: RingInkWell(
                key: Key('power-${mode.name}'),
                onTap: () => setState(() => _power = mode),
                borderRadius: BorderRadius.circular(fieldRadius),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    border: Border.all(color: _power == mode ? AppColors.accentBorder : AppColors.border),
                    color: _power == mode ? AppColors.accent.withValues(alpha: 0.25) : Colors.transparent,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_power == mode ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: _power == mode ? AppColors.accentText : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(body, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
      SettingsSection.account => [
        Text('Conta', style: AppText.serif(24)),
        const SizedBox(height: 16),
        Text(
          widget.userName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        Text(widget.server, style: AppText.mono(12, letterSpacing: 0)),
        if (widget.email != null) Text(widget.email!, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Text(
          widget.onLogout == null
              ? 'Suas notas ficam neste aparelho e funcionam sem servidor. Entrar em um servidor é opcional.'
              : 'Suas notas desta conta ficam neste aparelho. A sincronização com o servidor ainda não existe.',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        // signed in there is nothing to press here yet: leaving the account is in the account menu, and what belongs on this
        // screen (name, password, deleting the account) waits for routes the server does not have
        if (widget.onLogout == null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlineTextButton(
              label: 'Conta e servidor',
              icon: Icons.dns_outlined,
              onPressed: () {
                Navigator.pop(context);
                widget.onAccount();
              },
            ),
          ),
        ],
      ],
      SettingsSection.trash => [
        Text('Lixeira', style: AppText.serif(24)),
        const SizedBox(height: 16),
        Text(
          'Páginas excluídas são mantidas por ${widget.ws.settings.retention} dias e depois removidas do disco definitivamente. Entradas do Cofre são apagadas na hora, sem passar pela lixeira.',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlineTextButton(
            label: 'Esvaziar lixeira (${widget.ws.counts.trash})',
            danger: true,
            icon: Icons.delete_outline,
            onPressed: widget.ws.counts.trash == 0
                ? null
                : () {
                    widget.ws.emptyTrash();
                    widget.onToast('Lixeira esvaziada');
                    setState(() {});
                  },
          ),
        ),
      ],
      SettingsSection.data => [
        Text('Importar / exportar', style: AppText.serif(24)),
        const SizedBox(height: 16),
        const Text('Exportar tudo', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 4),
        const Text(
          'Copia as páginas (sem o cofre nem a lixeira) para a área de transferência.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineTextButton(
              label: 'Markdown',
              icon: Icons.content_copy,
              onPressed: () => _copyAll('md'),
            ),
            OutlineTextButton(
              label: 'JSON',
              icon: Icons.content_copy,
              onPressed: () => _copyAll('json'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 4),
        const Text(
          'Importar arquivos .md e .txt chega em breve.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
      SettingsSection.ai => [
        Text('IA (opcional)', style: AppText.serif(24)),
        const SizedBox(height: 4),
        Text('desligada por padrão', style: AppText.mono(12, letterSpacing: 0)),
        const SizedBox(height: 20),
        const Text('Provedor', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<AiProvider>(
          key: const Key('ai-provider'),
          initialValue: _provider,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          decoration: const InputDecoration(isDense: true),
          items: [
            for (final p in aiProviders)
              DropdownMenuItem(
                value: p,
                child: Text(p.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (p) => setState(() => _provider = p ?? _provider),
        ),
        const SizedBox(height: 20),
        Text(
          _provider.local ? 'Endereço do servidor' : 'Chave de API',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey('ai-key-${_provider.id}'),
          obscureText: !_provider.local,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: _provider.local
              ? TextInputType.url
              : TextInputType.visiblePassword,
          decoration: InputDecoration(
            isDense: true,
            hintText: _provider.placeholder,
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1, right: 8),
              child: Icon(
                Icons.lock_outline,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
            Expanded(
              child: Text(
                'A chave será guardada cifrada no aparelho e nunca aparecerá em logs ou exportações. Neste protótipo ela ainda não é salva.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ],
    },
  );
}
