import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/auth_api.dart';
import '../../../../core/api/auth_messages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/servers_provider.dart';
import 'recovery_key_sheet.dart';

/// Login / sign-up form, shared by the mobile and desktop layouts.
/// Switches between the two modes inside the widget itself.
class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({
    super.key,
    this.onContinueOffline,
    this.onSignedIn,
    this.showSubtitle = false,
  });

  /// Runs once the person is signed in (a new account is signed in right after it is created).
  final void Function(Account user)? onSignedIn;

  /// Called when tapping "Continuar offline neste dispositivo".
  final VoidCallback? onContinueOffline;

  /// Shows the supporting line under the title (desktop layout).
  final bool showSubtitle;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  bool _register = false;
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _error = '', _notice = '';
  AuthField? _invalid;
  // the server said registration is off: "Criar conta" gives way to a plain sentence, as on the web
  bool _registrationClosed = false;

  /// Counts the login/sign-up switches: each one gives new keys to the texts that
  /// fade. With the same key coming back (A, B, A) the AnimatedSwitcher would have
  /// two identical children at the same time.
  int _switches = 0;
  bool _obscure = true;
  bool _keepSignedIn = true;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  FormMode get _mode => _register ? FormMode.register : FormMode.login;

  void _switchMode() => setState(() {
    _register = !_register;
    _switches++;
    _error = _notice = '';
    _invalid = null;
  });

  Future<void> _submit() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final problem = validateAuth(
      _mode,
      email: _email.text,
      username: _username.text,
      password: _password.text,
    );
    setState(() {
      _error = _notice = '';
      _invalid = problem?.field;
      if (problem != null) _error = problem.message;
    });
    if (problem != null) return;

    final server = ref.read(serverListControllerProvider).current.selected;
    final base = server?.baseUri;
    if (base == null) {
      setState(() => _error = 'Escolha um servidor para entrar.');
      return;
    }
    setState(() => _busy = true);
    final session = ref.read(authSessionProvider);
    final address = _email.text.trim();
    final password = _password.text;
    final register = _register;
    var created = false;
    try {
      if (register) {
        await session.register(base, address, _username.text.trim(), password);
        created = true;
      }
      final user = await session.login(
        base,
        address,
        password,
        keepSignedIn: _keepSignedIn,
      );
      if (!mounted) return;
      _password.clear();
      widget.onSignedIn?.call(user);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is AuthApiError && e.code == 'registration_disabled') {
          _registrationClosed = true;
          _register = false;
          _switches++;
        }
        if (created) {
          // the account exists; only the sign-in after it failed
          _register = false;
          _switches++;
          _notice = 'Conta criada. Entre com seu e-mail e senha.';
        } else {
          _error = messageFor(e, register ? FormMode.register : FormMode.login);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueOffline() {
    final callback = widget.onContinueOffline;
    if (callback != null) return callback();
    // opened from the notes ("Conta e servidor"), "continue offline" simply goes back to them
    final nav = Navigator.of(context);
    if (nav.canPop()) return nav.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notas locais chegam em breve.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Swap(
          child: Text(
            _register ? 'Criar nova conta' : 'Bem-vindo de volta',
            key: ValueKey(_switches),
            style: AppText.serif(30),
          ),
        ),
        if (widget.showSubtitle) ...[
          const SizedBox(height: 8),
          _Swap(
            child: Text(
              _register
                  ? 'Crie sua conta para começar a escrever.'
                  : 'Entre para continuar de onde você parou.',
              key: ValueKey(_switches),
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
        const SizedBox(height: 24),
        // The username field comes in by opening space, and going out closes it.
        _Swap(
          resize: true,
          child: _register
              ? Column(
                  key: ValueKey('username-block-$_switches'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('Username'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('username-field'),
                      controller: _username,
                      enabled: !_busy,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newUsername],
                      decoration: _decoration(
                        'seu_usuario',
                        _invalid == AuthField.username,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                )
              : SizedBox.shrink(key: ValueKey('no-username-$_switches')),
        ),
        const _FieldLabel('E-mail'),
        const SizedBox(height: 8),
        TextField(
          key: const Key('email-field'),
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: _decoration(
            'voce@casa.local',
            _invalid == AuthField.email,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: _FieldLabel('Senha')),
            const SizedBox(width: 8),
            _MonoAction(
              label: _obscure ? 'MOSTRAR' : 'OCULTAR',
              onTap: () => setState(() => _obscure = !_obscure),
            ),
          ],
        ),
        const SizedBox(height: 0),
        TextField(
          key: const Key('password-field'),
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          autofillHints: [
            _register ? AutofillHints.newPassword : AutofillHints.password,
          ],
          onSubmitted: (_) => unawaited(_submit()),
          decoration: _decoration('••••••••••', _invalid == AuthField.password),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // the label may take two lines rather than an ellipsis: "Manter co…" says nothing
            Flexible(
              flex: 3,
              child: InkWell(
                onTap: () => setState(() => _keepSignedIn = !_keepSignedIn),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _keepSignedIn,
                      onChanged: (v) =>
                          setState(() => _keepSignedIn = v ?? false),
                      activeColor: AppColors.accent,
                      checkColor: AppColors.text,
                      side: const BorderSide(color: AppColors.accentBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Flexible(child: Text('Manter conectado')),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: InkWell(
                onTap: () => RecoveryKeySheet.show(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Chave de recuperação',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: AppColors.accentBorder),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _error,
            key: const Key('form-error'),
            style: const TextStyle(color: AppColors.offline, fontSize: 14),
          ),
        ],
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _notice,
            key: const Key('form-notice'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryButton,
            foregroundColor: AppColors.onPrimaryButton,
            minimumSize: const Size.fromHeight(54),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: Text(
            _busy
                ? (_register ? 'Criando conta…' : 'Entrando…')
                : (_register ? 'Criar conta' : 'Entrar'),
          ),
        ),
        const SizedBox(height: 20),
        const _OrDivider(),
        const SizedBox(height: 20),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            minimumSize: const Size.fromHeight(54),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
          onPressed: _busy ? null : _continueOffline,
          child: const Text('Continuar offline neste dispositivo', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 24),
        if (_registrationClosed)
          const Text(
            registrationClosedMessage,
            key: Key('registration-closed'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _register ? 'Já tem conta? ' : 'Ainda não tem conta? ',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              InkWell(
                key: const ValueKey('toggle-mode'),
                onTap: _busy ? null : _switchMode,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      _register ? 'Entrar' : 'Criar conta',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

InputDecoration _decoration(String hint, bool invalid) => InputDecoration(
  hintText: hint,
  enabledBorder: invalid
      ? OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          borderSide: const BorderSide(color: AppColors.offline),
        )
      : null,
);

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600));
}

class _MonoAction extends StatelessWidget {
  const _MonoAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // a finger needs 44 dp: the label stays small, the hit area does not
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(widthFactor: 1, child: Text(label, style: AppText.mono(12))),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: AppColors.border, height: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('OU', style: AppText.mono(11)),
        ),
        line,
      ],
    );
  }
}

/// Switches [child] (by its `key`) with a 200 ms fade; with [resize] the height
/// also animates. With "reduce motion" the switch is abrupt.
class _Swap extends StatelessWidget {
  const _Swap({required this.child, this.resize = false});

  final Widget child;
  final bool resize;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return child;
    final switcher = AnimatedSwitcher(
      duration: _duration,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: child,
    );
    if (!resize) return switcher;
    return AnimatedSize(
      duration: _duration,
      alignment: Alignment.topCenter,
      child: switcher,
    );
  }
}
