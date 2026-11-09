import { fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AuthApiError, type Account } from '../../api/auth'
import type { Auth } from '../../stores/auth.svelte'
import { selection } from '../../stores/servers.svelte'
import AuthForm from './AuthForm.svelte'
import { messageFor, validate } from './authMessages'

const user: Account = { id: '11111111-1111-1111-1111-111111111111', email: 'ana@casa.local', username: 'ana' }

/** A session that answers from a script. */
function fakeAuth(over: Partial<Record<'login' | 'register', unknown>> = {}) {
  const auth = {
    login: vi.fn(async () => user),
    register: vi.fn(async () => user),
    ...over,
  }
  return auth as unknown as Auth & typeof auth
}

const email = () => screen.getByLabelText('E-mail') as HTMLInputElement
const password = () => screen.getByLabelText('Senha') as HTMLInputElement
const username = () => screen.getByLabelText('Username') as HTMLInputElement
const type = (el: HTMLElement, value: string) => fireEvent.input(el, { target: { value } })
const submit = () => fireEvent.submit(email().closest('form')!)

async function fill(mail = 'ana@casa.local', pass = 'senha-forte-1') {
  await type(email(), mail)
  await type(password(), pass)
}

beforeEach(() => {
  selection.registrationEnabled = null
})
afterEach(() => {
  selection.registrationEnabled = null
})

describe('AuthForm — entrar', () => {
  it('sends what was typed (the e-mail trimmed, the password as it is) and reports who signed in', async () => {
    const auth = fakeAuth()
    const onsignedin = vi.fn()
    render(AuthForm, { auth, onsignedin })
    await fill('  ana@casa.local  ', '  com espaços  ')
    await submit()
    await waitFor(() => expect(onsignedin).toHaveBeenCalledWith(user))
    expect(auth.login).toHaveBeenCalledWith('ana@casa.local', '  com espaços  ', true)
  })

  it('"Manter conectado" off is passed on', async () => {
    const auth = fakeAuth()
    render(AuthForm, { auth })
    await fill()
    await fireEvent.click(screen.getByLabelText('Manter conectado'))
    await submit()
    await waitFor(() => expect(auth.login).toHaveBeenCalledWith('ana@casa.local', 'senha-forte-1', false))
  })

  it('wrong password says so, keeps the e-mail, and leaves the form usable', async () => {
    const auth = fakeAuth({ login: vi.fn(async () => Promise.reject(new AuthApiError(401, 'invalid_credentials'))) })
    const onsignedin = vi.fn()
    render(AuthForm, { auth, onsignedin })
    await fill()
    await submit()
    expect((await screen.findByTestId('form-error')).textContent).toBe('E-mail ou senha incorretos.')
    expect(email().value).toBe('ana@casa.local')
    expect(onsignedin).not.toHaveBeenCalled()
    expect((screen.getByRole('button', { name: 'Entrar' }) as HTMLButtonElement).disabled).toBe(false)
  })

  it('an empty form is stopped before any request, with the field marked and focused', async () => {
    const auth = fakeAuth()
    render(AuthForm, { auth })
    await submit()
    expect(screen.getByTestId('form-error').textContent).toBe('Informe um e-mail válido.')
    expect(email().getAttribute('aria-invalid')).toBe('true')
    expect(document.activeElement).toBe(email())
    await type(email(), 'ana@casa.local')
    await submit()
    expect(screen.getByTestId('form-error').textContent).toBe('Digite a senha.')
    expect(auth.login).not.toHaveBeenCalled()
  })

  it('the button is locked while the request runs and tapping again does not send twice', async () => {
    let finish!: (u: Account) => void
    const auth = fakeAuth({ login: vi.fn(() => new Promise<Account>((r) => (finish = r))) })
    render(AuthForm, { auth })
    await fill()
    await submit()
    await submit()
    await submit()
    const busy = screen.getByRole('button', { name: 'Entrando…' }) as HTMLButtonElement
    expect(busy.disabled).toBe(true)
    expect(auth.login).toHaveBeenCalledTimes(1)
    finish(user)
    await waitFor(() => expect((screen.getByRole('button', { name: 'Entrar' }) as HTMLButtonElement).disabled).toBe(false))
  })

  it('every kind of failure has a sentence a person can act on', async () => {
    for (const [e, text] of [
      [new AuthApiError(503, 'server_busy', 5000), 'O servidor está ocupado agora. Tente de novo em instantes.'],
      [new AuthApiError(429, 'http_error'), 'Muitas tentativas. Aguarde um pouco e tente de novo.'],
      [new AuthApiError(0, 'network'), 'Não foi possível falar com o servidor. Confira a conexão.'],
      [new AuthApiError(0, 'timeout'), 'O servidor demorou demais para responder. Tente de novo.'],
      [new AuthApiError(500, 'internal_error'), 'O servidor teve um problema. Tente de novo em instantes.'],
      [new Error('boom'), 'Algo deu errado. Tente de novo.'],
    ] as const) {
      const auth = fakeAuth({ login: vi.fn(async () => Promise.reject(e)) })
      const { unmount } = render(AuthForm, { auth })
      await fill()
      await submit()
      expect((await screen.findByTestId('form-error')).textContent).toBe(text)
      unmount()
    }
  })
})

describe('AuthForm — criar conta', () => {
  const toRegister = () => fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))

  it('creates the account and signs in with the same data', async () => {
    const auth = fakeAuth()
    const onsignedin = vi.fn()
    render(AuthForm, { auth, onsignedin })
    await toRegister()
    await type(username(), '  ana_reis  ')
    await fill('ana@casa.local', 'senha-forte-1')
    await submit()
    await waitFor(() => expect(onsignedin).toHaveBeenCalledWith(user))
    expect(auth.register).toHaveBeenCalledWith('ana@casa.local', 'ana_reis', 'senha-forte-1')
    expect(auth.login).toHaveBeenCalledWith('ana@casa.local', 'senha-forte-1', true)
  })

  it('checks the username and the password length before asking the server', async () => {
    const auth = fakeAuth()
    render(AuthForm, { auth })
    await toRegister()
    await fill('ana@casa.local', 'curta')
    await type(username(), 'ab')
    await submit()
    expect(screen.getByTestId('form-error').textContent).toBe('O nome de usuário precisa ter de 3 a 32 caracteres.')
    await type(username(), 'ana')
    await submit()
    expect(screen.getByTestId('form-error').textContent).toBe('A senha precisa ter de 8 a 72 caracteres.')
    expect(auth.register).not.toHaveBeenCalled()
  })

  it('a password over 72 bytes is caught even when it is under 72 letters', async () => {
    expect(validate('register', { email: 'a@b.co', username: 'ana', password: 'é'.repeat(40) })?.field).toBe('password')
    expect(validate('register', { email: 'a@b.co', username: 'ana', password: 'a'.repeat(72) })).toBeNull()
    expect(validate('register', { email: 'a@b.co', username: 'ana', password: 'a'.repeat(73) })?.field).toBe('password')
  })

  it('e-mail already used says so and does not try to sign in', async () => {
    const auth = fakeAuth({ register: vi.fn(async () => Promise.reject(new AuthApiError(409, 'email_already_exists'))) })
    render(AuthForm, { auth })
    await toRegister()
    await type(username(), 'ana')
    await fill()
    await submit()
    expect((await screen.findByTestId('form-error')).textContent).toBe('Este e-mail já está cadastrado. Tente entrar.')
    expect(auth.login).not.toHaveBeenCalled()
  })

  it('a weak password is explained', async () => {
    const auth = fakeAuth({ register: vi.fn(async () => Promise.reject(new AuthApiError(400, 'invalid_input'))) })
    render(AuthForm, { auth })
    await toRegister()
    await type(username(), 'ana')
    await fill('ana@casa.local', 'password123')
    await submit()
    expect((await screen.findByTestId('form-error')).textContent).toBe('Essa senha é fraca ou comum demais. Escolha outra.')
  })

  it('if the account was made but the sign-in right after failed, the person is sent to sign in, not told it failed', async () => {
    const auth = fakeAuth({ login: vi.fn(async () => Promise.reject(new AuthApiError(0, 'network'))) })
    render(AuthForm, { auth })
    await toRegister()
    await type(username(), 'ana')
    await fill()
    await submit()
    expect((await screen.findByTestId('form-notice')).textContent).toBe('Conta criada. Entre com seu e-mail e senha.')
    expect(screen.queryByTestId('form-error')).toBeNull()
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(email().value).toBe('ana@casa.local')
  })

  it('switching between the two forms clears an old error', async () => {
    const auth = fakeAuth({ login: vi.fn(async () => Promise.reject(new AuthApiError(401, 'invalid_credentials'))) })
    render(AuthForm, { auth })
    await fill()
    await submit()
    await screen.findByTestId('form-error')
    await toRegister()
    expect(screen.queryByTestId('form-error')).toBeNull()
  })
})

describe('AuthForm — cadastro fechado', () => {
  it('replaces "Criar conta" by the notice when the server says registration is closed', async () => {
    selection.registrationEnabled = false
    render(AuthForm, { auth: fakeAuth() })
    expect(screen.getByTestId('registration-closed').textContent).toBe('Novos registros estão desativados no momento.')
    expect(screen.queryByRole('button', { name: 'Criar conta' })).toBeNull()
  })

  it('an unknown answer keeps "Criar conta" (the form must not hide it because the server has not spoken yet)', () => {
    selection.registrationEnabled = null
    render(AuthForm, { auth: fakeAuth() })
    expect(screen.getByRole('button', { name: 'Criar conta' })).toBeTruthy()
    expect(screen.queryByTestId('registration-closed')).toBeNull()
  })

  it('closing while the person is on the register form takes them back to signing in', async () => {
    render(AuthForm, { auth: fakeAuth() })
    await fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))
    expect(screen.getByLabelText('Username')).toBeTruthy()
    selection.registrationEnabled = false
    await waitFor(() => expect(screen.queryByLabelText('Username')).toBeNull())
    expect(screen.getByTestId('registration-closed')).toBeTruthy()
  })

  it('a server that refuses at the moment of registering closes the option', async () => {
    const auth = fakeAuth({ register: vi.fn(async () => Promise.reject(new AuthApiError(403, 'registration_disabled'))) })
    render(AuthForm, { auth })
    await fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))
    await type(username(), 'ana')
    await fill()
    await submit()
    await waitFor(() => expect(screen.getByTestId('registration-closed')).toBeTruthy())
    expect(selection.registrationEnabled).toBe(false)
  })
})

describe('AuthForm — texto estranho', () => {
  it('huge, odd and empty-looking input never reaches the server unchecked', () => {
    expect(validate('login', { email: 'a'.repeat(300) + '@b.co', username: '', password: 'x' })?.field).toBe('email')
    expect(validate('login', { email: 'ana @casa.local', username: '', password: 'x' })?.field).toBe('email')
    expect(validate('login', { email: '@', username: '', password: 'x' })?.field).toBe('email')
    expect(validate('login', { email: '   ', username: '', password: 'x' })?.field).toBe('email')
    expect(validate('register', { email: 'a@b.co', username: '😀😀😀', password: 'senha-forte-1' })).toBeNull()
    expect(validate('register', { email: 'a@b.co', username: '😀'.repeat(33), password: 'senha-forte-1' })?.field).toBe('username')
  })

  it('messages never leak the server\'s English text or the status code', () => {
    for (const code of ['validation_failed', 'invalid_input', 'weird_new_code']) {
      const text = messageFor(new AuthApiError(422, code), 'register')
      expect(text).not.toMatch(/[a-z]+_[a-z]+/)
      expect(text).not.toContain('422')
    }
  })
})
