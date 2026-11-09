import { AuthApiError } from '../../api/auth'

export type FormMode = 'login' | 'register'

const TOO_MANY = 'Muitas tentativas. Aguarde um pouco e tente de novo.'

/** What to tell the person about a failed request, in plain words (the server's own messages are in English). */
export function messageFor(error: unknown, mode: FormMode): string {
  if (!(error instanceof AuthApiError)) return 'Algo deu errado. Tente de novo.'
  switch (error.code) {
    case 'invalid_credentials':
      return 'E-mail ou senha incorretos.'
    case 'email_already_exists':
      return 'Este e-mail já está cadastrado. Tente entrar.'
    case 'registration_disabled':
      return 'Os cadastros estão desativados neste servidor.'
    case 'validation_failed':
      return mode === 'register'
        ? 'Confira os campos: um e-mail válido, usuário de 3 a 32 caracteres e senha de 8 a 72 caracteres.'
        : 'Confira o e-mail e a senha.'
    case 'invalid_input':
      return mode === 'register' ? 'Essa senha é fraca ou comum demais. Escolha outra.' : 'Confira o e-mail e a senha.'
    case 'server_busy':
      return 'O servidor está ocupado agora. Tente de novo em instantes.'
    case 'payload_too_large':
      return 'Os dados enviados são grandes demais.'
    case 'network':
      return 'Não foi possível falar com o servidor. Confira a conexão.'
    case 'timeout':
      return 'O servidor demorou demais para responder. Tente de novo.'
  }
  if (error.status === 429) return TOO_MANY
  if (error.status >= 500) return 'O servidor teve um problema. Tente de novo em instantes.'
  return 'Algo deu errado. Tente de novo.'
}

const EMAIL_MAX = 254

/** The first thing wrong with what was typed, or null. The server checks again; this only saves a round trip. */
export function validate(mode: FormMode, v: { email: string; username: string; password: string }): { field: 'email' | 'username' | 'password'; message: string } | null {
  const email = v.email.trim()
  if (!/^[^\s@]+@[^\s@]+$/.test(email) || email.length > EMAIL_MAX) return { field: 'email', message: 'Informe um e-mail válido.' }
  if (mode === 'register') {
    const length = [...v.username.trim()].length
    if (length < 3 || length > 32) return { field: 'username', message: 'O nome de usuário precisa ter de 3 a 32 caracteres.' }
    const bytes = new TextEncoder().encode(v.password).length
    if (bytes < 8 || bytes > 72) return { field: 'password', message: 'A senha precisa ter de 8 a 72 caracteres.' }
  } else if (!v.password) return { field: 'password', message: 'Digite a senha.' }
  return null
}
