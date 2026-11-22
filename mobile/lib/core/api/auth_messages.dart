import 'dart:convert';

import 'auth_api.dart';

enum FormMode { login, register }

enum AuthField { email, username, password }

class FieldProblem {
  const FieldProblem(this.field, this.message);
  final AuthField field;
  final String message;
}

const tooManyMessage = 'Muitas tentativas. Aguarde um pouco e tente de novo.';
const registrationClosedMessage = 'Novos registros estão desativados no momento.';

/// What to tell the person about a failed request, in plain words (the server's own messages are in English).
String messageFor(Object error, FormMode mode) {
  if (error is! AuthApiError) return 'Algo deu errado. Tente de novo.';
  switch (error.code) {
    case 'invalid_credentials':
      return 'E-mail ou senha incorretos.';
    case 'email_already_exists':
      return 'Este e-mail já está cadastrado. Tente entrar.';
    case 'registration_disabled':
      return 'Os cadastros estão desativados neste servidor.';
    case 'validation_failed':
      return mode == FormMode.register
          ? 'Confira os campos: um e-mail válido, usuário de 3 a 32 caracteres e senha de 8 a 72 caracteres.'
          : 'Confira o e-mail e a senha.';
    case 'invalid_input':
      return mode == FormMode.register ? 'Essa senha é fraca ou comum demais. Escolha outra.' : 'Confira o e-mail e a senha.';
    case 'server_busy':
      return 'O servidor está ocupado agora. Tente de novo em instantes.';
    case 'payload_too_large':
      return 'Os dados enviados são grandes demais.';
    case 'network':
      return 'Não foi possível falar com o servidor. Confira a conexão.';
    case 'tls':
      return 'Não foi possível confirmar a identidade do servidor. Pareie com ele de novo.';
    case 'timeout':
      return 'O servidor demorou demais para responder. Tente de novo.';
    case 'bad_reply':
      return 'Esse endereço não respondeu como um servidor Pindrel.';
  }
  if (error.status == 429) return tooManyMessage;
  if (error.status >= 500) return 'O servidor teve um problema. Tente de novo em instantes.';
  return 'Algo deu errado. Tente de novo.';
}

const _emailMax = 254;
final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+$');

/// The first thing wrong with what was typed, or null. The server checks again; this only saves a round trip.
FieldProblem? validateAuth(FormMode mode, {required String email, required String username, required String password}) {
  final address = email.trim();
  if (!_emailShape.hasMatch(address) || address.length > _emailMax) {
    return const FieldProblem(AuthField.email, 'Informe um e-mail válido.');
  }
  if (mode == FormMode.register) {
    final length = username.trim().runes.length;
    if (length < 3 || length > 32) {
      return const FieldProblem(AuthField.username, 'O nome de usuário precisa ter de 3 a 32 caracteres.');
    }
    final bytes = utf8.encode(password).length;
    if (bytes < 8 || bytes > 72) {
      return const FieldProblem(AuthField.password, 'A senha precisa ter de 8 a 72 caracteres.');
    }
  } else if (password.isEmpty) {
    return const FieldProblem(AuthField.password, 'Digite a senha.');
  }
  return null;
}
