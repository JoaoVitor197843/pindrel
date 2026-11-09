import 'fake-indexeddb/auto'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ErrorHttp, LoginRefreshResponse, UserSummary } from './types/shared/protos/auth'
import { ServerInfo } from './types/shared/protos/server'
import App from './App.svelte'
import { auth } from './lib/stores/auth.svelte'
import { session } from './lib/stores/files.svelte'
import { viewport } from './test/setup'
import { stubLocalStorage } from './test/storage'

const ACCOUNT = { id: '22222222-2222-2222-2222-222222222222', email: 'ana@casa.local', username: 'ana' }
const bin = (b: Uint8Array) => b as unknown as BodyInit
const tokens = () => new Response(bin(LoginRefreshResponse.encode({ accessToken: 'a.b.c', expiresIn: 900 }).finish()), { status: 200 })
const err = (status: number, code: string) => new Response(bin(ErrorHttp.encode({ code, message: 'x' }).finish()), { status })

let calls: string[]
let data: Map<string, string>
/** The server: answers the auth routes and /server/info/; `over` replaces any of them. */
function server(over: Record<string, () => Response> = {}) {
  vi.mocked(fetch).mockImplementation((async (input: RequestInfo | URL) => {
    const path = String(input)
    calls.push(path)
    if (over[path]) return over[path]()
    switch (path) {
      case '/auth/login/':
      case '/auth/refresh/':
        return tokens()
      case '/auth/me/':
        return new Response(bin(UserSummary.encode(ACCOUNT).finish()), { status: 200 })
      case '/auth/logout/':
        return new Response(null, { status: 204 })
      case '/server/info/':
        return new Response(bin(ServerInfo.encode({ name: 'Casa', registrationEnabled: true }).finish()), { status: 200 })
    }
    return new Response(null, { status: 404 })
  }) as typeof fetch)
}

const databases = async () => (await indexedDB.databases()).map((d) => d.name)

async function signIn() {
  await fireEvent.input(screen.getByLabelText('E-mail'), { target: { value: ACCOUNT.email } })
  await fireEvent.input(screen.getByLabelText('Senha'), { target: { value: 'senha-forte-1' } })
  await fireEvent.submit(screen.getByLabelText('E-mail').closest('form')!)
}

beforeEach(async () => {
  viewport.set(1400)
  // every test starts on a browser with no databases
  for (const d of await indexedDB.databases()) if (d.name) indexedDB.deleteDatabase(d.name)
  calls = []
  data = stubLocalStorage()
  session.token = null
  await auth.logout()
  data.clear()
  calls = []
  history.replaceState(null, '', '/')
  server()
})

describe('App — conta', () => {
  it('entrar abre o painel da conta, com o banco só dela e sem páginas de exemplo', async () => {
    render(App)
    await signIn()
    expect(await screen.findByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
    expect(location.search).toBe('?tela=painel&modo=conta')
    expect(await screen.findByTestId('empty')).toBeTruthy()
    await waitFor(async () => expect(await databases()).toContain(`pindrel-cloud-${ACCOUNT.id}`))
    expect(await databases()).not.toContain('pindrel-local')
    expect(session.token).toBe('a.b.c')
    expect(data.get('pindrel:account')).toBe('1')
    // a signed-in account keeps the "shared with me" list, which local mode hides
    expect(screen.getByRole('button', { name: /Compartilhadas comigo/ })).toBeTruthy()
    expect(screen.getByRole('button', { name: /Menu da conta de ana/ })).toBeTruthy()
  })

  it('o painel da conta pergunta ao servidor como ele está (o modo local não)', async () => {
    render(App)
    await signIn()
    await screen.findByRole('heading', { name: 'Minhas páginas' })
    await waitFor(() => expect(calls.filter((c) => c === '/server/info/').length).toBeGreaterThan(0))
  })

  it('o que a pessoa escreve na conta fica no banco da conta e volta depois de recarregar', async () => {
    render(App)
    await signIn()
    await fireEvent.click(await screen.findByRole('button', { name: 'Criar primeira página' }))
    await fireEvent.click(screen.getAllByTestId('page-card')[0].querySelector('button')!)
    await fireEvent.input(await screen.findByRole('textbox', { name: /título/i }), { target: { value: 'Da conta' } })
    window.dispatchEvent(new Event('pagehide'))
    await new Promise((r) => setTimeout(r, 60))
    cleanup()

    // a reload: the cookie is turned back into a session before anything shows
    history.replaceState(null, '', '/')
    render(App)
    expect(await screen.findByText('Da conta')).toBeTruthy()
    expect(location.search).toBe('?tela=painel&modo=conta')
    expect(calls).toContain('/auth/refresh/')
  })

  it('duas contas no mesmo navegador não veem as notas uma da outra', async () => {
    render(App)
    await signIn()
    await fireEvent.click(await screen.findByRole('button', { name: 'Criar primeira página' }))
    await screen.findByRole('textbox', { name: /título/i }).catch(() => null)
    window.dispatchEvent(new Event('pagehide'))
    await new Promise((r) => setTimeout(r, 60))
    cleanup()
    await auth.logout()

    const other = '33333333-3333-3333-3333-333333333333'
    server({ '/auth/me/': () => new Response(bin(UserSummary.encode({ ...ACCOUNT, id: other, username: 'bia' }).finish()), { status: 200 }) })
    history.replaceState(null, '', '/')
    render(App)
    await signIn()
    expect(await screen.findByTestId('empty')).toBeTruthy()
    expect(await databases()).toEqual(expect.arrayContaining([`pindrel-cloud-${ACCOUNT.id}`, `pindrel-cloud-${other}`]))
  })

  it('sair volta ao login, esquece o aparelho e não deixa nenhuma nota na memória', async () => {
    render(App)
    await signIn()
    await screen.findByRole('heading', { name: 'Minhas páginas' })
    await fireEvent.click(screen.getByRole('button', { name: /Menu da conta de ana/ }))
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Sair' }))
    expect(await screen.findByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(location.search).toBe('')
    expect(data.has('pindrel:account')).toBe(false)
    expect(session.token).toBeNull()
    await waitFor(() => expect(calls).toContain('/auth/logout/'))
    // a reload now stays on the login
    cleanup()
    calls = []
    render(App)
    expect(screen.getByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(calls).not.toContain('/auth/refresh/')
  })

  it('um aparelho que já entrou volta direto ao painel, sem mostrar o login antes', async () => {
    data.set('pindrel:account', '1')
    render(App)
    expect(screen.queryByRole('heading', { name: 'Bem-vindo de volta' })).toBeNull()
    expect(await screen.findByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })

  it('o cookie que não vale mais manda para o login e esquece o aparelho', async () => {
    data.set('pindrel:account', '1')
    server({ '/auth/refresh/': () => err(401, 'invalid_refresh_token') })
    render(App)
    expect(await screen.findByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(data.has('pindrel:account')).toBe(false)
  })

  it('um endereço de conta sem sessão cai no login', async () => {
    server({ '/auth/refresh/': () => err(401, 'invalid_refresh_token') })
    history.replaceState(null, '', '/?tela=painel&modo=conta')
    render(App)
    expect(await screen.findByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(location.search).toBe('')
  })

  it('o modo local nunca fala com o servidor, nem num aparelho que já entrou', async () => {
    data.set('pindrel:account', '1')
    history.replaceState(null, '', '/?tela=painel&modo=local')
    render(App)
    expect(await screen.findByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
    await new Promise((r) => setTimeout(r, 100))
    expect(calls.filter((c) => c.startsWith('/auth/') || c === '/server/info/')).toEqual([])
  })

  it('senha errada fica na tela de login, com o aviso, e nada é lembrado', async () => {
    server({ '/auth/login/': () => err(401, 'invalid_credentials') })
    render(App)
    await signIn()
    expect((await screen.findByTestId('form-error')).textContent).toBe('E-mail ou senha incorretos.')
    expect(data.has('pindrel:account')).toBe(false)
    expect(location.search).toBe('')
  })

  it('o servidor derrubando a sessão com o painel aberto leva ao login com um aviso', async () => {
    render(App)
    await signIn()
    await screen.findByRole('heading', { name: 'Minhas páginas' })
    // the next renewal is refused: the cookie was revoked somewhere else
    server({ '/auth/refresh/': () => err(401, 'invalid_refresh_token') })
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(Date.now() + 20 * 60_000)
    document.dispatchEvent(new Event('visibilitychange'))
    vi.useRealTimers()
    expect(await screen.findByRole('heading', { name: 'Bem-vindo de volta' })).toBeTruthy()
    expect(screen.getByText('Sua sessão terminou. Entre de novo.')).toBeTruthy()
  })
})
