// The magnifier: how large the text of the pages is. A small panel under the header button (a slider, a step each way
// and a way back to the normal size), the same on the phone and on a desktop; Ctrl +, Ctrl - and Ctrl 0 do the same
// from the keyboard (see `editor_page.dart`).

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/note_page.dart';
import '../../data/workspace.dart';
import 'ui.dart';

String percent(double scale) => '${(scale * 100).round()}%';

Future<void> showTextSizePanel(BuildContext context, Workspace ws) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          // under the header, at the right, where the button is
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 64,
            right: 12,
            left: 12,
          ),
          child: TextSizePanel(ws: ws),
        ),
      ),
    );

class TextSizePanel extends StatelessWidget {
  const TextSizePanel({super.key, required this.ws});
  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('text-size-panel'),
      color: AppColors.surface,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListenableBuilder(
        listenable: ws,
        builder: (context, _) {
          final scale = ws.settings.textScale;
          // it never needs more than the screen has, even with the system's text at its largest
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 320,
              maxHeight:
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.paddingOf(context).top -
                          76)
                      .clamp(120.0, 4000.0),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'TAMANHO DO TEXTO',
                            style: monoLabel(size: 10, spacing: 1.4),
                          ),
                        ),
                        Text(
                          percent(scale),
                          key: const Key('text-size-value'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        GhostIconButton(
                          icon: Icons.remove,
                          tooltip: 'Diminuir o texto',
                          size: 40,
                          iconSize: 18,
                          onPressed: scale > minTextScale + 0.01
                              ? () => ws.setTextScale(scale - textScaleStep)
                              : null,
                        ),
                        Expanded(
                          child: Slider(
                            value: scale,
                            min: minTextScale,
                            max: maxTextScale,
                            divisions:
                                ((maxTextScale - minTextScale) / textScaleStep)
                                    .round(),
                            label: percent(scale),
                            onChanged: ws.setTextScale,
                          ),
                        ),
                        GhostIconButton(
                          icon: Icons.add,
                          tooltip: 'Aumentar o texto',
                          size: 40,
                          iconSize: 18,
                          onPressed: scale < maxTextScale - 0.01
                              ? () => ws.setTextScale(scale + textScaleStep)
                              : null,
                        ),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'No teclado: Ctrl + e Ctrl −',
                          style: AppText.mono(11, letterSpacing: 0),
                        ),
                        TextButton(
                          onPressed: scale == 1.0
                              ? null
                              : () => ws.setTextScale(1.0),
                          child: const Text('Tamanho normal'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
