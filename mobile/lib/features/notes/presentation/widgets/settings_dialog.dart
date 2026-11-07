import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/note_page.dart';
import '../../data/transfer.dart';
import '../../data/workspace.dart';
import 'ui.dart';

enum SettingsSection { general, account, trash, data }

const _nav = {
  SettingsSection.general: 'Geral',
  SettingsSection.account: 'Conta',
  SettingsSection.trash: 'Lixeira',
  SettingsSection.data: 'Importar/Exportar',
};

/// The settings in sections: a list on the left on wide screens, two steps of one screen on a phone.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.ws, this.section = SettingsSection.general, required this.userName, required this.server, required this.onAccount, required this.onToast});
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

  void _save() {
    widget.ws.saveSettings(Settings(useTrash: _useTrash, retention: _days.round()));
    widget.onToast('Configurações salvas');
    Navigator.pop(context);
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
    widget.onToast(pages.isEmpty ? 'Nada para exportar' : 'Copiado: ${pages.length} ${pages.length == 1 ? 'página' : 'páginas'}');
  }

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.sizeOf(context).width < 640;
    final title = stacked && !_atList ? _nav[_section]! : 'Configurações';
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fieldRadius), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              if (stacked && !_atList) GhostIconButton(icon: Icons.arrow_back, tooltip: 'Voltar para as seções', iconSize: 20, onPressed: () => setState(() => _atList = true)),
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(title, style: AppText.serif(20)))),
              GhostIconButton(icon: Icons.close, tooltip: 'Fechar configurações', iconSize: 20, onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(
            child: stacked
                ? (_atList ? _list(stacked) : _content())
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(width: 192, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.4), border: const Border(right: BorderSide(color: AppColors.border))), child: _list(stacked))),
                    Expanded(child: _content()),
                  ]),
          ),
          if (!(stacked && _atList))
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlineTextButton(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                CreamButton(label: 'Salvar', height: 40, onPressed: _save),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _list(bool stacked) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
        for (final e in _nav.entries)
          Material(
            color: !stacked && _section == e.key ? AppColors.accent.withValues(alpha: 0.45) : Colors.transparent,
            borderRadius: BorderRadius.circular(fieldRadius),
            child: RingInkWell(
              borderRadius: BorderRadius.circular(fieldRadius),
              onTap: () => setState(() {
                _section = e.key;
                _atList = false;
              }),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Text(e.value, style: TextStyle(fontSize: 15, color: !stacked && _section == e.key ? AppColors.accentText : AppColors.text))),
            ),
          ),
      ]);

  Widget _content() => ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: switch (_section) {
        SettingsSection.general => [
            Text('Geral', style: AppText.serif(24)),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('Usar a lixeira', style: TextStyle(fontSize: 15))),
              Semantics(
                toggled: _useTrash,
                label: 'Usar a lixeira',
                child: RingInkWell(
                  onTap: () => setState(() => _useTrash = !_useTrash),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    key: const Key('trash-switch'),
                    width: 48,
                    height: 28,
                    padding: const EdgeInsets.all(2),
                    alignment: _useTrash ? Alignment.centerRight : Alignment.centerLeft,
                    decoration: BoxDecoration(color: _useTrash ? AppColors.accent : AppColors.background, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.fieldBorder)),
                    child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(_useTrash ? 'Páginas excluídas ficam guardadas por um tempo.' : 'Páginas excluídas somem na hora.', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            Opacity(
              opacity: _useTrash ? 1 : 0.6,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Dias de retenção da lixeira', style: TextStyle(fontSize: 15)),
                Row(children: [
                  Expanded(child: Slider(min: 7, max: 90, divisions: 83, value: _days, onChanged: _useTrash ? (v) => setState(() => _days = v) : null)),
                  SizedBox(width: 64, child: Text('${_days.round()} dias', textAlign: TextAlign.right, style: AppText.mono(12, letterSpacing: 0))),
                ]),
              ]),
            ),
          ],
        SettingsSection.account => [
            Text('Conta', style: AppText.serif(24)),
            const SizedBox(height: 16),
            Text(widget.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text(widget.server, style: AppText.mono(12, letterSpacing: 0)),
            const SizedBox(height: 12),
            const Text('Suas notas ficam neste aparelho e funcionam sem servidor. Entrar em um servidor é opcional.', style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5)),
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
        SettingsSection.trash => [
            Text('Lixeira', style: AppText.serif(24)),
            const SizedBox(height: 16),
            Text('Páginas excluídas são mantidas por ${widget.ws.settings.retention} dias e depois removidas do disco definitivamente. Entradas do Cofre são apagadas na hora, sem passar pela lixeira.', style: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5)),
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
            const Text('Copia as páginas (sem o cofre nem a lixeira) para a área de transferência.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlineTextButton(label: 'Markdown', icon: Icons.content_copy, onPressed: () => _copyAll('md')),
              OutlineTextButton(label: 'JSON', icon: Icons.content_copy, onPressed: () => _copyAll('json')),
            ]),
            const SizedBox(height: 24),
            const Text('Importar', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 4),
            const Text('Importar arquivos .md e .txt chega em breve.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
      });
}
