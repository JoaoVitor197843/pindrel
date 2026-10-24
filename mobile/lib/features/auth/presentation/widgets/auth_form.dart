import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'recovery_key_sheet.dart';

/// Login / sign-up form, shared by the mobile and desktop layouts.
/// Switches between the two modes inside the widget itself.
class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    this.onContinueOffline,
    this.showSubtitle = false,
  });

  /// Called when tapping "Continuar offline neste dispositivo".
  final VoidCallback? onContinueOffline;

  /// Shows the supporting line under the title (desktop layout).
  final bool showSubtitle;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  bool _register = false;

  /// Counts the login/sign-up switches: each one gives new keys to the texts that
  /// fade. With the same key coming back (A, B, A) the AnimatedSwitcher would have
  /// two identical children at the same time.
  int _switches = 0;
  bool _obscure = true;
  bool _keepSignedIn = true;

  void _continueOffline() {
    final callback = widget.onContinueOffline;
    if (callback != null) return callback();
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
                  children: const [
                    _FieldLabel('Username'),
                    SizedBox(height: 8),
                    TextField(
                      key: Key('username-field'),
                      autocorrect: false,
                      decoration: InputDecoration(hintText: 'seu_usuario'),
                    ),
                    SizedBox(height: 20),
                  ],
                )
              : SizedBox.shrink(key: ValueKey('no-username-$_switches')),
        ),
        const _FieldLabel('E-mail'),
        const SizedBox(height: 8),
        const TextField(
          key: Key('email-field'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(hintText: 'voce@casa.local'),
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
        const SizedBox(height: 8),
        TextField(
          key: const Key('password-field'),
          obscureText: _obscure,
          decoration: const InputDecoration(hintText: '••••••••••'),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
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
                    const Flexible(
                      child: Text(
                        'Manter conectado',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
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
          // The auth API integration does not exist yet.
          onPressed: () {},
          child: Text(_register ? 'Criar conta' : 'Entrar'),
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
          onPressed: _continueOffline,
          child: const Text('Continuar offline neste dispositivo'),
        ),
        const SizedBox(height: 24),
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
              onTap: () => setState(() {
                _register = !_register;
                _switches++;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _register ? 'Entrar' : 'Criar conta',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label, style: AppText.mono(12)),
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
