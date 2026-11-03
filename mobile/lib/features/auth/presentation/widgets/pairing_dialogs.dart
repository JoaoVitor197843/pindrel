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
  PairingFailure.badRoom =>
    'Esse código de sala não existe (mais): pode ter vencido, ter sido digitado errado ou já ter outro aparelho. Gere um novo na página do servidor.',
  PairingFailure.badCode =>
    'O código mestre foi recusado, ou este servidor não provou conhecê-lo. Ele vale uma vez e pode já ter sido trocado: veja a linha mais recente "código mestre" no registro (log) do gateway.',
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

PairingFlow _makeFlow(WidgetRef ref, Uri base, FlowMode mode, String room, String master) => PairingFlow(
  base: base,
  mode: mode,
  room: room,
  master: master,
  store: ref.read(pairedStoreProvider),
  pairer: ref.read(digitsPairerProvider),
  masterPairer: ref.read(masterPairerProvider),
  offerFor: ref.read(tlsOfferProvider),
);

/// Shared plumbing of the two screens: owns the flow, redraws on every change, and when the server is paired hands it to the
/// list (it becomes the chosen one and trusted) and closes with `true`.
mixin _FlowHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  PairingFlow? flow;
  bool _closed = false;

  void begin(Uri base, FlowMode mode, {String room = '', String master = ''}) {
    flow?.removeListener(_changed);
    flow?.cancel();
    final f = _makeFlow(ref, base, mode, room, master);
    flow = f..addListener(_changed);
    onBegin();
    unawaited(f.start());
    if (mounted) setState(() {});
  }

  void onBegin() {}

  /// The name the person gave the server, if the screen asks for one.
  String givenName() => '';

  void _changed() {
    final f = flow;
    if (f == null || !mounted) return;
    if (f.state.phase == FlowPhase.paired && !_closed) {
      _closed = true;
      final controller = ref.read(serverListControllerProvider);
      final store = ref.read(pairedStoreProvider);
      final label = givenName();
      unawaited(() async {
        var paired = f.state.paired!;
        if (label.isNotEmpty) {
          // the name the person gave it is kept with the pairing
          paired = paired.withLabel(label);
          await store.save(paired);
        }
        await controller.completePairing(ServerOption.fromPaired(paired));
        if (mounted) Navigator.of(context).pop(true);
      }());
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

const _roomHint =
    'Na página de conexão do servidor, ou na tela de login do web, toque em "Gerar código de pareamento": aparece um código de 4 dígitos.';

/// Only digits, at most four: the code of a room.
final _roomFormatters = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];

Widget _masterField(TextEditingController controller, {required bool enabled, required ValueChanged<String> onChanged, String? errorText}) {
  return TextField(
    key: const ValueKey('master-field'),
    controller: controller,
    enabled: enabled,
    autocorrect: false,
    enableSuggestions: false,
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [LengthLimitingTextInputFormatter(40)],
    onChanged: onChanged,
    style: AppText.mono(16, color: AppColors.text, letterSpacing: 2),
    decoration: InputDecoration(
      labelText: AddServerDialog.masterLabel,
      hintText: 'XXXX-XXXX-XXXX-XXXX',
      errorText: errorText,
      helperMaxLines: 3,
      helperText: 'Está no registro (log) do gateway, na linha "PAIR: código mestre". Vale uma vez.',
    ),
  );
}

/// A server announced on the network that this device has not opened before. The person opens a room on a page of the server
/// and types its 4-digit code here; then the app shows six numbers, that page shows six numbers, and the person says whether
/// they are the same. With the master code from the server's log there is nothing to compare.
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
  final _room = TextEditingController();
  final _master = TextEditingController();
  bool _useMaster = false;
  bool _failedWithMaster = false;

  /// Whether the server has a secure side (`null` while asking).
  bool? _tls;

  @override
  void initState() {
    super.initState();
    unawaited(_checkTls());
  }

  Future<void> _checkTls() async {
    final base = widget.server.baseUri;
    if (base == null) return setState(() => _tls = false);
    if (base.scheme == 'https') return setState(() => _tls = true);
    final offer = await ref.read(tlsOfferProvider)(base);
    if (mounted) setState(() => _tls = offer != null);
  }

  @override
  void dispose() {
    _room.dispose();
    _master.dispose();
    super.dispose();
  }

  bool get _ready => _useMaster ? parseMasterCode(_master.text) != null : _room.text.length == 4;

  void _go() {
    final base = widget.server.baseUri;
    if (base == null || !_ready) return;
    _failedWithMaster = _useMaster;
    if (_useMaster) {
      begin(base, FlowMode.master, master: _master.text);
    } else {
      begin(base, FlowMode.compare, room: _room.text);
    }
  }

  /// Back to the first step (a wrong room code, a refused master code), keeping what is worth keeping.
  void _again() {
    flow?.removeListener(_changed);
    flow?.cancel();
    setState(() {
      flow = null;
      _room.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final title = 'Parear com ${server.name}';
    final cancel = TextButton(
      onPressed: () {
        flow?.reject();
        Navigator.of(context).pop(false);
      },
      child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
    );
    final loading = _frame(
      title: title,
      body: const [
        Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Procurando a conexão segura…', style: _muted)),
          ],
        ),
      ],
      actions: [cancel],
    );
    if (_tls == null) return loading;
    if (_tls == false) {
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
            child: const Text('Usar sem criptografia', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            autofocus: true,
            style: _primary(),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
        ],
      );
    }
    final state = flow?.state;
    if (state == null) {
      // the first step: the room code (or the master code)
      return _frame(
        title: title,
        body: [
          Text(
            _useMaster
                ? 'Digite o código mestre que o gateway mostra no registro (log). O app e o servidor provam um ao outro que o conhecem, e não é preciso comparar números.'
                : '$_roomHint Digite-o aqui. Se preferir abrir a página no navegador: http://${server.address}/server/connect/?ficar',
            style: _muted,
          ),
          const SizedBox(height: 14),
          if (_useMaster)
            _masterField(_master, enabled: true, onChanged: (_) => setState(() {}))
          else
            TextField(
              key: const ValueKey('room-field'),
              controller: _room,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: _roomFormatters,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _go(),
              style: AppText.mono(28, color: AppColors.text, letterSpacing: 8),
              decoration: const InputDecoration(labelText: AddServerDialog.roomLabel, hintText: '0000'),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('master-toggle'),
              onPressed: () => setState(() => _useMaster = !_useMaster),
              child: Text(
                _useMaster ? 'Voltar para o código da sala' : 'Tenho o código mestre',
                style: const TextStyle(color: AppColors.accentBorder),
              ),
            ),
          ),
        ],
        actions: [
          cancel,
          FilledButton(
            key: const ValueKey('pairing-go'),
            style: _primary(),
            onPressed: _ready ? _go : null,
            child: Text(_useMaster ? 'Parear com o código mestre' : 'Continuar'),
          ),
        ],
      );
    }
    switch (state.phase) {
      case FlowPhase.looking:
      case FlowPhase.renewing:
        return _frame(
          title: title,
          body: [
            Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.phase == FlowPhase.renewing ? 'Gerando novos números…' : 'Falando com o servidor…',
                    style: _muted,
                  ),
                ),
              ],
            ),
          ],
          actions: [cancel],
        );
      case FlowPhase.noTls:
        return loading; // not reached: the first step already looked for the secure side
      case FlowPhase.showing:
        final prompt = state.prompt!;
        return _frame(
          title: title,
          body: [
            Text(
              'Sala ${_room.text}. Na página do servidor, confira se os números abaixo são os mesmos que aparecem lá.',
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
                    style: AppText.mono(40, color: AppColors.text, letterSpacing: 6),
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
        final reason = state.failure ?? PairingFailure.protocol;
        // a wrong room code or a refused master code is fixed by typing again; the rest can be retried as it was
        final retypes = reason == PairingFailure.badRoom || reason == PairingFailure.badCode;
        return _frame(
          title: title,
          body: [Text(pairingFailureText(reason), style: _muted)],
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fechar', style: TextStyle(color: AppColors.textMuted)),
            ),
            FilledButton(
              autofocus: true,
              style: _primary(),
              onPressed: () {
                if (retypes) {
                  _useMaster = _failedWithMaster && reason == PairingFailure.badCode;
                  _again();
                } else {
                  _go();
                }
              },
              child: Text(retypes ? 'Digitar outro código' : 'Tentar de novo'),
            ),
          ],
        );
    }
  }
}

/// "Adicionar servidor": the address, an optional name and, as required fields, the code of a room opened on a page of the
/// server and the six numbers that page then shows (switched on once the server was reached; cleared whenever new numbers
/// replace the old ones). With the master code from the server's log those two are replaced by that one code.
class AddServerDialog extends ConsumerStatefulWidget {
  const AddServerDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AddServerDialog(),
  );

  static const title = 'Adicionar servidor';
  static const addressLabel = 'Endereço do servidor';
  static const nameLabel = 'Nome do servidor (opcional)';
  static const roomLabel = 'Código da sala (obrigatório)';
  static const codeLabel = 'Código de 6 dígitos (obrigatório)';
  static const masterLabel = 'Código mestre (obrigatório)';

  @override
  ConsumerState<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<AddServerDialog>
    with _FlowHost<AddServerDialog> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _room = TextEditingController();
  final _master = TextEditingController();
  final _code = TextEditingController();
  String? _addressError;
  String? _roomError;
  String? _codeError;
  bool _useMaster = false;
  int _lastRound = 0;
  int _lastWrong = 0;

  @override
  String givenName() => cleanLabel(_name.text);

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _room.dispose();
    _master.dispose();
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
    _roomError = null;
    if (_useMaster) {
      if (parseMasterCode(_master.text) == null) {
        setState(() => _roomError = 'O código mestre tem 16 letras e números (XXXX-XXXX-XXXX-XXXX).');
        return;
      }
    } else if (_room.text.length != 4) {
      setState(() => _roomError = 'Digite o código da sala (4 dígitos). $_roomHint');
      return;
    }
    _codeError = null;
    _lastRound = 0;
    _lastWrong = 0;
    if (_useMaster) {
      begin(uri, FlowMode.master, master: _master.text);
    } else {
      begin(uri, FlowMode.type, room: _room.text);
    }
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
    final locked = flow != null && !failed && !noTls; // what was typed is fixed once the search started
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
          textInputAction: TextInputAction.next,
          style: AppText.mono(14, color: AppColors.text, letterSpacing: 0.5),
          decoration: InputDecoration(
            labelText: AddServerDialog.addressLabel,
            hintText: '192.168.1.5:8080',
            errorText: _addressError,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('server-name-field'),
          controller: _name,
          enabled: !locked,
          maxLength: PairingCode.maxNameLength,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            labelText: AddServerDialog.nameLabel,
            hintText: 'Se vazio, usa o nome que o servidor informa',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        if (_useMaster)
          _masterField(
            _master,
            enabled: !locked,
            errorText: _roomError,
            onChanged: (_) => setState(() => _roomError = null),
          )
        else
          TextField(
            key: const ValueKey('room-field'),
            controller: _room,
            enabled: !locked,
            keyboardType: TextInputType.number,
            inputFormatters: _roomFormatters,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() => _roomError = null),
            onSubmitted: (_) => _search(),
            style: AppText.mono(22, color: AppColors.text, letterSpacing: 6),
            decoration: InputDecoration(
              labelText: AddServerDialog.roomLabel,
              hintText: '0000',
              errorText: _roomError,
              errorMaxLines: 4,
              helperMaxLines: 4,
              helperText: _roomHint,
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('master-toggle'),
            onPressed: locked ? null : () => setState(() {
              _useMaster = !_useMaster;
              _roomError = null;
            }),
            child: Text(
              _useMaster ? 'Voltar para o código da sala' : 'Tenho o código mestre',
              style: TextStyle(color: locked ? AppColors.textMuted : AppColors.accentBorder),
            ),
          ),
        ),
        if (!_useMaster) ...[
          const SizedBox(height: 8),
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
                  ? 'Digite os 6 números que a página do servidor mostra na sua sala.'
                  : 'Os 6 números aparecem na página do servidor depois que você buscar.',
            ),
          ),
        ],
        if (searching) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(
                phase == FlowPhase.renewing ? 'Gerando novos números…' : 'Procurando o servidor…',
                style: _muted,
              ),
            ],
          ),
        ],
        if (showing) ...[
          const SizedBox(height: 14),
          Text(
            'Servidor encontrado: ${state!.prompt!.name} (${state.prompt!.hostPort})',
            key: const ValueKey('found-server'),
            style: _muted,
          ),
          const SizedBox(height: 10),
          _Countdown(until: state.prompt!.expiresAt, total: sasConfirmTimeout),
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
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
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
            child: Text(
              failed || noTls ? 'Tentar de novo' : (_useMaster ? 'Parear com o código mestre' : 'Buscar servidor'),
            ),
          ),
      ],
    );
  }
}

/// What the person decides about a server they trust.
enum RevokeChoice { cancel, remove, repair }

/// "Remover confiança": the device forgets the pairing and, if the person wants, pairs again right away.
class RevokeTrustDialog extends StatelessWidget {
  const RevokeTrustDialog({super.key, required this.server, required this.chosen});

  final ServerOption server;

  /// The server is the one in use now.
  final bool chosen;

  static Future<RevokeChoice> show(BuildContext context, ServerOption server, {required bool chosen}) async =>
      await showDialog<RevokeChoice>(
        context: context,
        builder: (_) => RevokeTrustDialog(server: server, chosen: chosen),
      ) ??
      RevokeChoice.cancel;

  @override
  Widget build(BuildContext context) {
    return _frame(
      title: 'Remover confiança em ${server.name}?',
      body: [
        const Text(
          'Este aparelho deixa de confiar na chave de segurança deste servidor e esquece que você já o abriu. '
          'Para usá-lo de novo, será preciso parear outra vez, comparando os 6 números.',
          style: _muted,
        ),
        if (chosen) ...[
          const SizedBox(height: 10),
          const Text('Ele também deixa de ser o servidor escolhido.', style: _muted),
        ],
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(RevokeChoice.cancel),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          key: const ValueKey('revoke-remove'),
          onPressed: () => Navigator.of(context).pop(RevokeChoice.remove),
          child: const Text('Remover confiança', style: TextStyle(color: AppColors.offline)),
        ),
        FilledButton(
          key: const ValueKey('revoke-repair'),
          style: _primary(),
          onPressed: () => Navigator.of(context).pop(RevokeChoice.repair),
          child: const Text('Remover e parear de novo'),
        ),
      ],
    );
  }
}
