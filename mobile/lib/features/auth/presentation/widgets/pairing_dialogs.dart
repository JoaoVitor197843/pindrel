import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/pairing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/pairing_flow.dart';
import '../../data/server_address.dart';
import '../../data/server_option.dart';
import '../providers/servers_provider.dart';

/// What the person is told when pairing did not happen.
String pairingFailureText(PairingFailure reason) => switch (reason) {
  PairingFailure.busy =>
    'Outro aparelho está pareando com este servidor agora. Tente de novo em um minuto.',
  PairingFailure.locked =>
    'Houve tentativas demais deste aparelho. Aguarde alguns minutos e tente de novo.',
  PairingFailure.unreachable =>
    'Não consegui falar com o servidor. Confira se ele está ligado, na mesma rede, e se a porta segura (HTTPS) está liberada no firewall.',
  PairingFailure.declined =>
    'Os números não eram iguais, então nada foi guardado. Se não foi um engano, desconfie deste servidor.',
  PairingFailure.expired =>
    'Os números expiraram várias vezes sem resposta. Tente de novo quando estiver com o servidor à vista.',
  PairingFailure.fingerprintMismatch ||
  PairingFailure.notACertificate ||
  PairingFailure.protocol =>
    'Este servidor respondeu algo inesperado. Ele pode ser de outra versão do Pindrel.',
};

ButtonStyle _primary() => FilledButton.styleFrom(
  backgroundColor: AppColors.primaryButton,
  foregroundColor: AppColors.onPrimaryButton,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radius),
  ),
);

Widget _frame({
  required String title,
  required List<Widget> body,
  required List<Widget> actions,
}) {
  return AlertDialog(
    backgroundColor: AppColors.surface,
    elevation: 0,
    scrollable: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      side: const BorderSide(color: AppColors.border),
    ),
    title: Text(title, style: AppText.serif(22)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: body,
    ),
    actions: actions,
  );
}

const _muted = TextStyle(color: AppColors.textMuted, height: 1.4);

/// "Novos números em 42 s", counting down to when the server forgets the digits (and the bar with it).
class _Countdown extends StatefulWidget {
  const _Countdown({required this.until, required this.total});

  final DateTime until;
  final Duration total;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    final fraction = (left.inMilliseconds / widget.total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    return Semantics(
      label: 'Novos números em $seconds segundos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: AppColors.border,
              color: AppColors.accentBorder,
            ),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              'Novos números em ${seconds}s',
              style: AppText.mono(11),
            ),
          ),
        ],
      ),
    );
  }
}

PairingFlow _makeFlow(WidgetRef ref, Uri base, FlowMode mode) => PairingFlow(
  base: base,
  mode: mode,
  store: ref.read(pairedStoreProvider),
  pairer: ref.read(digitsPairerProvider),
  offerFor: ref.read(tlsOfferProvider),
);

/// Shared plumbing of the two screens: owns the flow, redraws on every change, and when the server is paired hands it to the
/// list (it becomes the chosen one and trusted) and closes with `true`.
mixin _FlowHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  PairingFlow? flow;
  bool _closed = false;

  void begin(Uri base, FlowMode mode) {
    flow?.removeListener(_changed);
    flow?.cancel();
    final f = _makeFlow(ref, base, mode);
    flow = f..addListener(_changed);
    onBegin();
    unawaited(f.start());
    if (mounted) setState(() {});
  }

  void onBegin() {}

  void _changed() {
    final f = flow;
    if (f == null || !mounted) return;
    if (f.state.phase == FlowPhase.paired && !_closed) {
      _closed = true;
      final paired = f.state.paired!;
      final controller = ref.read(serverListControllerProvider);
      unawaited(
        controller.completePairing(ServerOption.fromPaired(paired)).then((_) {
          if (mounted) Navigator.of(context).pop(true);
        }),
      );
    }
    onChanged(f.state);
    setState(() {});
  }

  void onChanged(PairingFlowState state) {}

  @override
  void dispose() {
    flow?.removeListener(_changed);
    flow?.cancel();
    flow?.dispose();
    super.dispose();
  }
}

/// A server announced on the network that this device has not opened before: the app shows six numbers, the server's
/// connection page shows six numbers, and the person says whether they are the same.
class PairingDialog extends ConsumerStatefulWidget {
  const PairingDialog({super.key, required this.server});

  final ServerOption server;

  static Future<bool?> show(BuildContext context, ServerOption server) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PairingDialog(server: server),
      );

  @override
  ConsumerState<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends ConsumerState<PairingDialog>
    with _FlowHost<PairingDialog> {
  @override
  void initState() {
    super.initState();
    final base = widget.server.baseUri;
    if (base != null) begin(base, FlowMode.compare);
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final state = flow?.state ?? const PairingFlowState();
    final title = 'Parear com ${server.name}';
    final cancel = TextButton(
      onPressed: () {
        flow?.reject();
        Navigator.of(context).pop(false);
      },
      child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
    );
    switch (state.phase) {
      case FlowPhase.looking:
      case FlowPhase.renewing:
        return _frame(
          title: title,
          body: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.phase == FlowPhase.renewing
                        ? 'Gerando novos números…'
                        : 'Procurando a conexão segura…',
                    style: _muted,
                  ),
                ),
              ],
            ),
          ],
          actions: [cancel],
        );
      case FlowPhase.noTls:
        return _frame(
          title: title,
          body: const [
            Text(
              'Este servidor não oferece conexão segura (HTTPS). Você pode usá-lo mesmo assim, mas o que for enviado '
              'pela rede, inclusive a senha, não ficará criptografado.',
              style: _muted,
            ),
          ],
          actions: [
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                final controller = ref.read(serverListControllerProvider);
                final ok = await controller.select(server, confirmed: true);
                if (nav.mounted) nav.pop(ok);
              },
              child: const Text(
                'Usar sem criptografia',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              autofocus: true,
              style: _primary(),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
          ],
        );
      case FlowPhase.showing:
        final prompt = state.prompt!;
        return _frame(
          title: title,
          body: [
            Text(
              'Abra a página de conexão do servidor (no navegador, em '
              'http://${server.address}/) ou veja o registro do gateway. '
              'Confira se os números abaixo são os mesmos que aparecem lá.',
              style: _muted,
            ),
            const SizedBox(height: 18),
            Center(
              child: Semantics(
                label: 'Número de conferência: ${prompt.digits.split('').join(' ')}',
                child: ExcludeSemantics(
                  child: Text(
                    prompt.grouped,
                    key: const ValueKey('pairing-digits'),
                    style: AppText.mono(
                      40,
                      color: AppColors.text,
                      letterSpacing: 6,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Countdown(until: prompt.expiresAt, total: sasConfirmTimeout),
            const SizedBox(height: 14),
            const Text(
              'Se forem diferentes, toque em Cancelar: pode ser outro aparelho da rede se passando por este servidor.',
              style: _muted,
            ),
          ],
          actions: [
            cancel,
            FilledButton(
              style: _primary(),
              onPressed: () => flow?.confirmSame(),
              child: const Text('São iguais'),
            ),
          ],
        );
      case FlowPhase.paired:
      case FlowPhase.cancelled:
        return _frame(title: title, body: const [], actions: const []);
      case FlowPhase.failed:
        return _frame(
          title: title,
          body: [
            Text(
              pairingFailureText(state.failure ?? PairingFailure.protocol),
              style: _muted,
            ),
          ],
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Fechar',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              autofocus: true,
              style: _primary(),
              onPressed: () {
                final base = widget.server.baseUri;
                if (base != null) begin(base, FlowMode.compare);
              },
              child: const Text('Tentar de novo'),
            ),
          ],
        );
    }
  }
}

/// "Adicionar servidor": the address and, as a required field, the six numbers the server shows. The numbers exist only after
/// the server has been reached, so the field is switched on then; it is cleared whenever new numbers replace the old ones.
class AddServerDialog extends ConsumerStatefulWidget {
  const AddServerDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AddServerDialog(),
  );

  static const title = 'Adicionar servidor';
  static const addressLabel = 'Endereço do servidor';
  static const codeLabel = 'Código de 6 dígitos (obrigatório)';

  @override
  ConsumerState<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<AddServerDialog>
    with _FlowHost<AddServerDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  String? _addressError;
  String? _codeError;
  Uri? _target;
  int _lastRound = 0;
  int _lastWrong = 0;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  void onChanged(PairingFlowState state) {
    // new digits replace the old ones: what was typed for them is worthless
    if (state.round != _lastRound) {
      _lastRound = state.round;
      _code.clear();
      _codeError = null;
    }
    if (state.wrongTries > _lastWrong) {
      final left = 3 - state.wrongTries;
      _codeError =
          'Não confere com o do servidor. ${left == 1 ? 'Resta 1 tentativa' : 'Restam $left tentativas'}.';
      _code.clear();
    }
    _lastWrong = state.wrongTries;
  }

  void _search() {
    final uri = parseServerAddress(_address.text);
    if (uri == null) {
      setState(
        () => _addressError = _address.text.trim().isEmpty
            ? 'Digite o endereço do servidor.'
            : 'Isso não parece um endereço. Exemplo: 192.168.1.5:8080',
      );
      return;
    }
    _addressError = null;
    _codeError = null;
    _lastRound = 0;
    _lastWrong = 0;
    _target = uri;
    begin(uri, FlowMode.type);
  }

  void _submit() => flow?.submit(_code.text);

  @override
  Widget build(BuildContext context) {
    final state = flow?.state;
    final phase = state?.phase;
    final searching = phase == FlowPhase.looking || phase == FlowPhase.renewing;
    final showing = phase == FlowPhase.showing;
    final failed = phase == FlowPhase.failed;
    final noTls = phase == FlowPhase.noTls;
    final locked = flow != null && !failed && !noTls; // the address is fixed once the search started
    final target = _target;
    return _frame(
      title: AddServerDialog.title,
      body: [
        TextField(
          controller: _address,
          enabled: !locked,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _search(),
          style: AppText.mono(14, color: AppColors.text, letterSpacing: 0.5),
          decoration: InputDecoration(
            labelText: AddServerDialog.addressLabel,
            hintText: '192.168.1.5:8080',
            errorText: _addressError,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pairing-code-field'),
          controller: _code,
          enabled: showing,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _codeError = null),
          onSubmitted: (_) {
            if (_code.text.length == 6) _submit();
          },
          style: AppText.mono(22, color: AppColors.text, letterSpacing: 6),
          decoration: InputDecoration(
            labelText: AddServerDialog.codeLabel,
            hintText: '000000',
            errorText: _codeError,
            helperMaxLines: 4,
            helperText: showing
                ? 'Digite os 6 números que a página de conexão do servidor mostra (abra '
                      'http://${target?.host}:${target?.port}/ num navegador).'
                : 'Os números aparecem na página do servidor depois que você buscar.',
          ),
        ),
        if (searching) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                phase == FlowPhase.renewing
                    ? 'Gerando novos números…'
                    : 'Procurando o servidor…',
                style: _muted,
              ),
            ],
          ),
        ],
        if (showing) ...[
          const SizedBox(height: 14),
          _Countdown(until: state!.prompt!.expiresAt, total: sasConfirmTimeout),
        ],
        if (noTls) ...[
          const SizedBox(height: 14),
          const Text(
            'Este servidor não oferece conexão segura (HTTPS), então não há o que parear. Você pode usá-lo sem '
            'criptografia pelo menu de servidores, se ele aparecer na rede.',
            style: _muted,
          ),
        ],
        if (failed) ...[
          const SizedBox(height: 14),
          Text(
            pairingFailureText(state!.failure ?? PairingFailure.protocol),
            style: _muted,
          ),
        ],
      ],
      actions: [
        TextButton(
          onPressed: () {
            flow?.reject();
            Navigator.of(context).pop(false);
          },
          child: const Text(
            'Cancelar',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        if (showing)
          FilledButton(
            style: _primary(),
            onPressed: _code.text.length == 6 ? _submit : null,
            child: const Text('Parear'),
          )
        else
          FilledButton(
            style: _primary(),
            onPressed: searching ? null : _search,
            child: Text(failed || noTls ? 'Tentar de novo' : 'Buscar servidor'),
          ),
      ],
    );
  }
}
