import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/auth_header.dart';
import '../widgets/recovery_key_sheet.dart';

/// Tela de login / cadastro. Alterna entre os dois modos no próprio widget.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.onContinueOffline});

  /// Chamado ao tocar em "Continuar offline neste dispositivo".
  final VoidCallback? onContinueOffline;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _register = false;
  bool _obscure = true;
  bool _keepSignedIn = true;

  void _continueOffline() {
    final callback = widget.onContinueOffline;
    if (callback != null) return callback();
    _showSoon('Notas locais chegam em breve.');
  }

  void _showSoon(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          AuthHeader(
            onAddServer: () => _showSoon('Adicionar servidor chega em breve.'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _register ? 'Criar nova conta' : 'Bem-vindo de volta',
          style: AppText.serif(30),
        ),
        const SizedBox(height: 24),
        if (_register) ...[
          const _FieldLabel('Username'),
          const SizedBox(height: 8),
          const TextField(
            key: Key('username-field'),
            autocorrect: false,
            decoration: InputDecoration(hintText: 'seu_usuario'),
          ),
          const SizedBox(height: 20),
        ],
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
            const _FieldLabel('Senha'),
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
            InkWell(
              onTap: () => RecoveryKeySheet.show(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Chave de recuperação',
                  style: TextStyle(color: AppColors.accentBorder),
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
          // A integração com a API de auth ainda não existe.
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
              onTap: () => setState(() => _register = !_register),
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
