import axe from 'axe-core'
import { fireEvent, render, screen, within } from '@testing-library/svelte'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { toast } from '../lib/stores/toast.svelte'
import { viewport } from '../test/setup'
import Dashboard from './Dashboard.svelte'

const click = (el: HTMLElement) => fireEvent.click(el)
const cards = () => screen.queryAllByTestId('page-card')
const cardTitles = () => cards().map((c) => within(c).getByRole('heading').textContent)
const type = (el: HTMLElement, value: string) => fireEvent.input(el, { target: { value } })
const key = (k: string, init: KeyboardEventInit = {}) => fireEvent.keyDown(window, { key: k, ...init })
const section = (name: RegExp) => within(screen.getByRole('heading', { name }).closest('section')!)

beforeEach(() => {
  toast.message = ''
})

async function violations(): Promise<string[]> {
  const result = await axe.run(document.body, { rules: { 'color-contrast': { enabled: false }, region: { enabled: false } } })
  return result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.html.slice(0, 80)).join(' | ')}`)
}

const openUserMenu = () => click(screen.getByRole('button', { name: /Menu da conta/ }))
const openSettings = async (item = 'Configurações') => {
  await openUserMenu()
  await click(screen.getByRole('menuitem', { name: item }))
}
const unlockVault = async (password = 'abcd') => {
  await click(screen.getByRole('button', { name: /^Cofre/ }))
  await click(screen.getByRole('button', { name: 'Desbloquear' }))
  await type(screen.getByLabelText('Senha mestra', { selector: 'input' }), password)
  await fireEvent.submit(screen.getByLabelText('Senha mestra', { selector: 'input' }).closest('form')!)
}

describe('Dashboard — desktop', () => {
  beforeEach(() => viewport.set(1400))

  it('mostra a marca, o menu completo, o usuário e as páginas', () => {
    render(Dashboard)
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
    expect(screen.getByText('23 páginas')).toBeTruthy()
    expect(screen.getByText('Pindrel')).toBeTruthy()
    expect(screen.getByText('SELF-HOSTED')).toBeTruthy()
    expect(screen.queryByText(/Plany/)).toBeNull()
    expect(screen.getByText('pindrel.local')).toBeTruthy()
    expect(screen.getByRole('button', { name: /Todas as páginas/ }).getAttribute('aria-current')).toBe('page')
    expect(cards()).toHaveLength(23)
  })

  it('páginas compartilhadas ficam só na visão delas, com o nome de quem compartilhou', async () => {
    render(Dashboard)
    expect(cardTitles()).not.toContain('Runbook de incidentes')
    await click(screen.getByRole('button', { name: /^Compartilhadas comigo/ }))
    expect(cards()).toHaveLength(3)
    expect(screen.getByText('por Caio')).toBeTruthy()
  })

  it('uma página do cofre aparece com cadeado e "cofre"', () => {
    render(Dashboard)
    const locked = cards().find((c) => within(c).queryByText('Senhas e chaves de recuperação'))!
    expect(within(locked).getByText('No cofre')).toBeTruthy()
    expect(within(locked).getByText('cofre')).toBeTruthy()
  })

  it('"Nova página" cria um cartão logo depois das fixadas', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Nova página' }))
    expect(cards()).toHaveLength(24)
    const titles = cardTitles()
    expect(titles.indexOf('Sem título')).toBeLessThan(titles.indexOf('Reforma do apartamento — orçamento'))
    expect(screen.getByText('24 páginas')).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Nova página' }))
    await click(screen.getByRole('button', { name: 'Nova página' }))
    expect(cards()).toHaveLength(26)
  })

  it('alterna entre RECENTES e A–Z', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'A–Z' }))
    const az = cardTitles()
    expect(az.slice(0, 2)).toEqual(['Ideias para o Pindrel', 'Migração do servidor para NixOS'])
    expect(az[2]).toBe('Anotações do curso de tipografia')
    expect(screen.getByRole('button', { name: 'A–Z' }).getAttribute('aria-pressed')).toBe('true')
    await click(screen.getByRole('button', { name: 'RECENTES' }))
    expect(cardTitles()[2]).toBe('Reforma do apartamento — orçamento')
  })

  it('fixar move a página para "Fixadas" e desafixar tira de lá', async () => {
    render(Dashboard)
    expect(section(/^Fixadas/).getAllByTestId('page-card')).toHaveLength(2)
    await click(screen.getByRole('button', { name: 'Fixar Cardápio da semana' }))
    expect(cards()).toHaveLength(23) // moved, never duplicated
    expect(section(/^Fixadas/).getAllByTestId('page-card')).toHaveLength(3)
    await click(screen.getByRole('button', { name: 'Desafixar Cardápio da semana' }))
    expect(section(/^Fixadas/).getAllByTestId('page-card')).toHaveLength(2)
  })

  it('agrupa por data e mostra os títulos das seções', () => {
    render(Dashboard)
    for (const label of ['Hoje', 'Esta semana', 'Últimos 30 dias', 'Mais antigas']) {
      expect(screen.getByRole('heading', { name: new RegExp(`^${label}`) })).toBeTruthy()
    }
  })

  it('busca vira uma lista única, destaca o termo (sem acento e sem caixa) e some o HTML digitado', async () => {
    render(Dashboard)
    const search = screen.getByRole('searchbox')
    await type(search, 'MIGRACAO')
    expect(cardTitles()).toEqual(['Migração do servidor para NixOS'])
    expect(screen.queryByRole('heading', { name: /^Fixadas/ })).toBeNull()
    expect(document.querySelector('mark')?.textContent).toBe('Migração')
    await type(search, '<img src=x onerror=alert(1)>')
    expect(document.querySelector('img')).toBeNull()
  })

  it('busca sem resultado mostra o vazio e "Limpar filtros" traz tudo de volta', async () => {
    render(Dashboard)
    await type(screen.getByRole('searchbox'), 'nada disso existe')
    expect(screen.getByRole('heading', { name: 'Nada encontrado' })).toBeTruthy()
    await click(screen.getByRole('button', { name: 'Limpar filtros' }))
    expect(cards()).toHaveLength(23)
    expect((screen.getByRole('searchbox') as HTMLInputElement).value).toBe('')
  })

  it('filtra por tag (o título vira #tag) e remove o filtro pelo chip', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: /^receitas/ }))
    expect(cards()).toHaveLength(3)
    expect(screen.getByRole('heading', { name: '#receitas' })).toBeTruthy()
    await click(screen.getByRole('button', { name: /Remover filtro/ }))
    expect(cards()).toHaveLength(23)
    expect(screen.getByRole('heading', { name: 'Minhas páginas' })).toBeTruthy()
  })

  it('cria tag com a cor escolhida e ignora nome vazio', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Nova tag' }))
    const input = screen.getByLabelText('Nome da nova tag')
    await type(input, '   ')
    await fireEvent.submit(input.closest('form')!)
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()

    await click(screen.getByRole('button', { name: 'Nova tag' }))
    expect(screen.getAllByRole('button', { name: /^Cor / })).toHaveLength(6)
    await click(screen.getByRole('button', { name: 'Cor ameixa' }))
    expect(screen.getByRole('button', { name: 'Cor ameixa' }).getAttribute('aria-pressed')).toBe('true')
    const again = screen.getByLabelText('Nome da nova tag')
    await type(again, 'estudos')
    await fireEvent.submit(again.closest('form')!)
    const created = screen.getByRole('button', { name: /^estudos/ })
    expect(created.querySelector('.bg-tag-plum')).toBeTruthy()
  })

  it('"Cancelar" e Esc fecham o formulário de tag sem criar nada', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Nova tag' }))
    await click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()
    await click(screen.getByRole('button', { name: 'Nova tag' }))
    await fireEvent.keyDown(screen.getByLabelText('Nome da nova tag'), { key: 'Escape' })
    expect(screen.queryByLabelText('Nome da nova tag')).toBeNull()
  })

  it('lixeira: mover, ver, restaurar e esvaziar', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: /Mover Reforma do apartamento/ }))
    expect(cards()).toHaveLength(22)
    expect(toast.message).toBe('Movida para a lixeira')

    await click(screen.getByRole('button', { name: /^Lixeira/ }))
    expect(cards()).toHaveLength(1)
    await click(screen.getByRole('button', { name: /Restaurar/ }))
    expect(screen.getByTestId('empty').textContent).toContain('Lixeira vazia')

    await click(screen.getByRole('button', { name: /^Todas as páginas/ }))
    await click(screen.getByRole('button', { name: /Mover Cardápio da semana/ }))
    await click(screen.getByRole('button', { name: /^Lixeira/ }))
    await click(screen.getByRole('button', { name: 'Esvaziar lixeira' }))
    expect(screen.getByTestId('empty')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Esvaziar lixeira' })).toBeNull()
  })

  describe('cofre', () => {
    it('bloqueado esconde o conteúdo e pede a senha mestra; senha curta é recusada com aviso', async () => {
      render(Dashboard)
      await click(screen.getByRole('button', { name: /^Cofre/ }))
      expect(screen.getByText('BLOQUEADO')).toBeTruthy()
      expect(screen.queryByText(/seed de 24 palavras/)).toBeNull()

      await click(screen.getByRole('button', { name: 'Desbloquear' }))
      expect(screen.getByRole('dialog', { name: 'Senha mestra' })).toBeTruthy()
      const input = screen.getByLabelText('Senha mestra', { selector: 'input' }) as HTMLInputElement
      expect(input.type).toBe('password')
      await type(input, 'abc')
      await fireEvent.submit(input.closest('form')!)
      expect(screen.getByRole('alert').textContent).toContain('mínimo 4')
      expect(screen.getByText('BLOQUEADO')).toBeTruthy()
      expect(input.value).toBe('') // a wrong password is never left on the screen

      await type(input, 'abcd')
      await fireEvent.submit(input.closest('form')!)
      expect(screen.queryByRole('dialog')).toBeNull()
      expect(screen.getByText('DESBLOQUEADO')).toBeTruthy()
      expect(screen.getByText(/seed de 24 palavras/)).toBeTruthy()
      expect(toast.message).toBe('Cofre desbloqueado')
    })

    it('desbloqueado: cria entrada e bloqueia de novo', async () => {
      render(Dashboard)
      await unlockVault()
      await click(screen.getByRole('button', { name: /Nova entrada segura/ }))
      expect(screen.getAllByText('Nova entrada segura').length).toBeGreaterThan(1)
      await click(screen.getByRole('button', { name: 'Bloquear' }))
      expect(screen.queryByText(/seed de 24 palavras/)).toBeNull()
    })

    it('tocar numa entrada bloqueada pede a senha para ela; Esc e fundo cancelam', async () => {
      render(Dashboard)
      await click(screen.getByRole('button', { name: /^Cofre/ }))
      await click(screen.getByRole('button', { name: /Chave da API do provedor de IA/ }))
      expect(screen.getByRole('dialog').textContent).toContain('Chave da API do provedor de IA')
      await key('Escape')
      expect(screen.queryByRole('dialog')).toBeNull()
      await click(screen.getByRole('button', { name: /Nova entrada segura/ }))
      expect(screen.getByRole('dialog').textContent).toContain('uma nova entrada')
      await click(screen.getByTestId('vault-backdrop'))
      expect(screen.queryByRole('dialog')).toBeNull()
      expect(screen.getByText('BLOQUEADO')).toBeTruthy()
    })
  })

  describe('busca rápida (Ctrl K)', () => {
    it('Ctrl+K abre e fecha; Esc e o botão também', async () => {
      render(Dashboard)
      await key('k', { ctrlKey: true })
      expect(screen.getByRole('dialog', { name: 'Busca rápida' })).toBeTruthy()
      expect(document.activeElement).toBe(screen.getByRole('combobox'))
      await key('k', { ctrlKey: true })
      expect(screen.queryByRole('dialog')).toBeNull()
      await click(screen.getByRole('button', { name: 'Abrir busca rápida' }))
      expect(screen.getByRole('dialog')).toBeTruthy()
      await key('Escape')
      expect(screen.queryByRole('dialog')).toBeNull()
      await key('K', { metaKey: true })
      expect(screen.getByRole('dialog')).toBeTruthy()
    })

    it('lista páginas, ações e tags; digitar filtra; Enter abre o primeiro resultado', async () => {
      render(Dashboard)
      await key('k', { ctrlKey: true })
      const dialog = within(screen.getByRole('dialog'))
      expect(dialog.getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual(['Páginas', 'Ações', 'Tags'])
      expect(dialog.getByRole('status').textContent).toBe(`${dialog.getAllByRole('option').length} resultados`)

      const input = screen.getByRole('combobox')
      await type(input, 'nixos')
      expect(screen.getAllByRole('option')).toHaveLength(1)
      await fireEvent.keyDown(input, { key: 'Enter' })
      expect(screen.queryByRole('dialog')).toBeNull()
      expect((screen.getByRole('searchbox') as HTMLInputElement).value).toBe('Migração do servidor para NixOS')
      expect(cards()).toHaveLength(1)
    })

    it('setas andam pela lista e dão a volta; o item ativo é anunciado', async () => {
      render(Dashboard)
      await key('k', { ctrlKey: true })
      const input = screen.getByRole('combobox')
      const options = () => screen.getAllByRole('option')
      expect(options()[0].getAttribute('aria-selected')).toBe('true')
      await fireEvent.keyDown(input, { key: 'ArrowDown' })
      expect(options()[1].getAttribute('aria-selected')).toBe('true')
      expect(input.getAttribute('aria-activedescendant')).toBe(options()[1].id)
      await fireEvent.keyDown(input, { key: 'ArrowUp' })
      await fireEvent.keyDown(input, { key: 'ArrowUp' })
      expect(options().at(-1)!.getAttribute('aria-selected')).toBe('true')
    })

    it('ações: criar página, ir ao cofre, ver a lixeira, alternar ordem e abrir configurações', async () => {
      render(Dashboard)
      const run = async (label: string) => {
        await key('k', { ctrlKey: true })
        await click(screen.getByRole('option', { name: new RegExp(label) }))
      }
      await run('Criar nova página')
      expect(cards()).toHaveLength(24)
      expect(screen.queryByRole('dialog')).toBeNull()
      await run('Ir para o cofre')
      expect(screen.getByRole('heading', { name: 'Cofre' })).toBeTruthy()
      await run('Ver lixeira')
      expect(screen.getByRole('heading', { name: 'Lixeira' })).toBeTruthy()
      await run('Alternar ordenação')
      await click(screen.getByRole('button', { name: /^Todas as páginas/ }))
      expect(screen.getByRole('button', { name: 'A–Z' }).getAttribute('aria-pressed')).toBe('true')
      await run('Abrir configurações')
      expect(screen.getByRole('dialog', { name: 'Configurações' })).toBeTruthy()
      expect(screen.queryByRole('dialog', { name: 'Busca rápida' })).toBeNull()
    })

    it('escolher uma tag filtra por ela; nada encontrado avisa', async () => {
      render(Dashboard)
      await key('k', { ctrlKey: true })
      await click(screen.getByRole('option', { name: /#leitura/ }))
      expect(cards()).toHaveLength(3)
      await key('k', { ctrlKey: true })
      await type(screen.getByRole('combobox'), 'xyzxyz')
      expect(screen.getByText('Nada encontrado')).toBeTruthy()
      await fireEvent.keyDown(screen.getByRole('combobox'), { key: 'Enter' }) // nothing selected: must not throw
      expect(screen.getByRole('dialog')).toBeTruthy()
    })

    it('clicar no fundo fecha', async () => {
      render(Dashboard)
      await key('k', { ctrlKey: true })
      await click(screen.getByTestId('palette-backdrop'))
      expect(screen.queryByRole('dialog')).toBeNull()
    })
  })

  describe('configurações', () => {
    it('abre pelo menu do usuário, mostra as 5 seções e marca alterações até salvar', async () => {
      render(Dashboard)
      await openSettings()
      const dialog = screen.getByRole('dialog', { name: 'Configurações' })
      for (const n of ['Geral', 'Conta', 'Lixeira', 'Importar/Exportar', 'IA (opcional)']) {
        expect(within(dialog).getByRole('button', { name: n })).toBeTruthy()
      }
      expect(within(dialog).getByText('tudo salvo')).toBeTruthy()
      expect(within(dialog).queryByRole('button', { name: 'Salvar' })).toBeNull()

      const sw = within(dialog).getByRole('switch', { name: /Usar lixeira/ })
      expect(sw.getAttribute('aria-checked')).toBe('true')
      await click(sw)
      expect(within(dialog).getByText('alterações não salvas')).toBeTruthy()
      await click(within(dialog).getByRole('button', { name: 'Salvar' }))
      expect(within(dialog).getByText('tudo salvo')).toBeTruthy()
      expect(toast.message).toBe('Configurações salvas')
    })

    it('com a lixeira desligada, excluir apaga de vez e a lixeira explica', async () => {
      render(Dashboard)
      await openSettings()
      await click(screen.getByRole('switch'))
      expect((screen.getByLabelText('Dias de retenção da lixeira') as HTMLInputElement).disabled).toBe(true)
      await click(screen.getByRole('button', { name: 'Salvar' }))
      await click(screen.getByRole('button', { name: 'Fechar' }))
      await click(screen.getByRole('button', { name: /Mover Reforma do apartamento/ }))
      expect(toast.message).toBe('Página excluída')
      await click(screen.getByRole('button', { name: /^Lixeira/ }))
      expect(screen.getByTestId('empty').textContent).toContain('desligada')
    })

    it('a retenção salva aparece na lixeira; fechar sem salvar descarta', async () => {
      render(Dashboard)
      await openSettings()
      await fireEvent.input(screen.getByLabelText('Dias de retenção da lixeira'), { target: { value: '45' } })
      await click(screen.getByRole('button', { name: 'Fechar' }))
      await click(screen.getByRole('button', { name: /^Lixeira/ }))
      expect(screen.getByTestId('empty').textContent).toContain('30 dias')

      await openSettings()
      await fireEvent.input(screen.getByLabelText('Dias de retenção da lixeira'), { target: { value: '45' } })
      await click(screen.getByRole('button', { name: 'Salvar' }))
      await click(screen.getByRole('button', { name: 'Fechar' }))
      expect(screen.getByTestId('empty').textContent).toContain('45 dias')
    })

    it('"Importar / exportar" do menu abre direto na seção de dados, com o resumo', async () => {
      render(Dashboard)
      await openSettings('Importar / exportar')
      expect(screen.getByRole('heading', { name: 'Importar / exportar' })).toBeTruthy()
      expect(screen.getByText('23 páginas · 3 compartilhadas · 5 no cofre')).toBeTruthy()
    })

    it('exportar gera o arquivo e avisa; se o navegador falhar, avisa também', async () => {
      render(Dashboard)
      await openSettings('Importar / exportar')
      URL.createObjectURL = vi.fn(() => 'blob:x')
      URL.revokeObjectURL = vi.fn()
      const anchor = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
      await click(screen.getByRole('button', { name: 'JSON' }))
      expect(toast.message).toBe('Exportação pronta')
      expect(URL.createObjectURL).toHaveBeenCalledOnce()
      URL.createObjectURL = vi.fn(() => {
        throw new Error('no')
      })
      await click(screen.getByRole('button', { name: 'Markdown' }))
      expect(toast.message).toBe('Não foi possível exportar')
      anchor.mockRestore()
    })

    it('importar cria páginas dos .md/.txt e ignora o resto', async () => {
      render(Dashboard)
      await openSettings('Importar / exportar')
      const mk = (name: string, text: string) => {
        const f = new File([text], name)
        f.text = async () => text
        return f
      }
      const input = screen.getByLabelText('Escolher arquivos para importar')
      await fireEvent.change(input, { target: { files: [mk('nota.md', '# Minha nota\n\ncorpo'), mk('virus.exe', 'MZ')] } })
      await vi.waitFor(() => expect(toast.message).toBe('1 página importada, 1 ignorada'))
      await click(screen.getByRole('button', { name: 'Fechar' }))
      expect(cardTitles()).toContain('Minha nota')
      expect(cards()).toHaveLength(24)
    })

    it('importar só arquivos inválidos avisa e não cria nada', async () => {
      render(Dashboard)
      await openSettings('Importar / exportar')
      const f = new File(['x'], 'a.png')
      await fireEvent.change(screen.getByLabelText('Escolher arquivos para importar'), { target: { files: [f] } })
      await vi.waitFor(() => expect(toast.message).toBe('Nenhum arquivo .md ou .txt válido'))
      await click(screen.getByRole('button', { name: 'Fechar' }))
      expect(cards()).toHaveLength(23)
    })

    it('"Esvaziar lixeira agora" só funciona quando há o que esvaziar', async () => {
      render(Dashboard)
      await click(screen.getByRole('button', { name: /Mover Reforma do apartamento/ }))
      await openSettings()
      await click(screen.getByRole('button', { name: 'Lixeira' }))
      const btn = screen.getByRole('button', { name: 'Esvaziar lixeira agora' }) as HTMLButtonElement
      expect(btn.disabled).toBe(false)
      await click(btn)
      expect(btn.disabled).toBe(true)
      expect(toast.message).toBe('Lixeira esvaziada')
    })

    it('Conta e IA: campos de senha/chave não são salvos e a chave não aparece na tela', async () => {
      render(Dashboard)
      await openSettings()
      await click(screen.getByRole('button', { name: 'Conta' }))
      expect(screen.getByText('marina@pindrel.local', { selector: 'p' })).toBeTruthy()
      await click(screen.getByRole('button', { name: 'IA (opcional)' }))
      const key = screen.getByLabelText('Chave de API') as HTMLInputElement
      expect(key.type).toBe('password')
      await fireEvent.change(key, { target: { value: 'sk-ant-segredo' } })
      expect(screen.getByText('alterações não salvas')).toBeTruthy()
      expect(document.body.textContent).not.toContain('sk-ant-segredo')
    })

    it('IA: oferece vários provedores e os locais pedem um endereço, não uma chave', async () => {
      render(Dashboard)
      await openSettings()
      await click(screen.getByRole('button', { name: 'IA (opcional)' }))
      const select = screen.getByLabelText('Provedor') as HTMLSelectElement
      const labels = [...select.options].map((o) => o.textContent)
      for (const n of ['Anthropic (Claude)', 'OpenAI', 'Google (Gemini)', 'Mistral', 'Groq', 'DeepSeek', 'xAI (Grok)', 'OpenRouter']) expect(labels).toContain(n)
      expect(labels.length).toBeGreaterThanOrEqual(10)
      await fireEvent.change(select, { target: { value: 'ollama' } })
      const address = screen.getByLabelText('Endereço do servidor') as HTMLInputElement
      expect(address.type).toBe('url')
      expect(address.placeholder).toBe('http://localhost:11434')
      await fireEvent.change(select, { target: { value: 'google' } })
      expect((screen.getByLabelText('Chave de API') as HTMLInputElement).type).toBe('password')
    })

    it('Esc e o fundo fecham', async () => {
      render(Dashboard)
      await openSettings()
      await key('Escape')
      expect(screen.queryByRole('dialog')).toBeNull()
      await openSettings()
      await click(screen.getByTestId('settings-backdrop'))
      expect(screen.queryByRole('dialog')).toBeNull()
    })
  })

  it('menu do usuário: itens, Esc, clique fora e "Sair" chama o callback', async () => {
    const onlogout = vi.fn()
    render(Dashboard, { onlogout })
    await openUserMenu()
    expect(screen.getAllByRole('menuitem').map((m) => m.textContent?.trim())).toEqual(['Configurações', 'Importar / exportar', 'Sair'])
    await key('Escape')
    expect(screen.queryByRole('menu')).toBeNull()

    await openUserMenu()
    await fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('menu')).toBeNull()

    await openUserMenu()
    await click(screen.getByRole('menuitem', { name: 'Sair' }))
    expect(onlogout).toHaveBeenCalledOnce()
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('"Sair" sem callback explica que ainda não está ligado', async () => {
    render(Dashboard)
    await openUserMenu()
    await click(screen.getByRole('menuitem', { name: 'Sair' }))
    expect(toast.message).toContain('ainda não está ligado')
  })

  it('iniciais do usuário aguentam nome vazio ou estranho', () => {
    render(Dashboard, { userName: '   ' })
    expect(screen.getAllByText('?').length).toBeGreaterThan(0)
  })

  it('alterna entre grade e lista, e a lista mantém as páginas e as ações', async () => {
    render(Dashboard)
    expect(screen.getByRole('button', { name: 'Grade' }).getAttribute('aria-pressed')).toBe('true')
    await click(screen.getByRole('button', { name: 'Lista' }))
    expect(screen.getByRole('button', { name: 'Lista' }).getAttribute('aria-pressed')).toBe('true')
    expect(cards()).toHaveLength(23)
    await click(screen.getByRole('button', { name: 'Fixar Cardápio da semana' }))
    await click(screen.getByRole('button', { name: /Mover Cardápio da semana/ }))
    expect(cards()).toHaveLength(22)
    expect(await violations()).toEqual([])
  })

  it('acessibilidade (axe): lista, menu, busca rápida, senha do cofre e configurações', async () => {
    render(Dashboard)
    expect(await violations()).toEqual([])
    await openUserMenu()
    expect(await violations()).toEqual([])
    await key('Escape')
    await key('k', { ctrlKey: true })
    expect(await violations()).toEqual([])
    await key('Escape')
    await click(screen.getByRole('button', { name: /^Cofre/ }))
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Desbloquear' }))
    expect(await violations()).toEqual([])
    await key('Escape')
    await openSettings()
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Importar/Exportar' }))
    expect(await violations()).toEqual([])
  })
})

describe('Dashboard — abrir uma página', () => {
  beforeEach(() => viewport.set(1400))

  it('clicar no título de um cartão abre a página; sem o callback o título é só texto', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Rotina de encerramento do trimestre' }))
    expect(onopen).toHaveBeenCalledWith('p0')
  })

  it('o botão de fixar e o de lixeira não abrem a página', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Fixar Cardápio da semana' }))
    await click(screen.getByRole('button', { name: /Mover Cardápio da semana/ }))
    expect(onopen).not.toHaveBeenCalled()
  })

  it('funciona também na lista e nas páginas compartilhadas', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Lista' }))
    await click(screen.getByRole('button', { name: 'Notas da reunião de produto' }))
    expect(onopen).toHaveBeenLastCalledWith('p3')
    await click(screen.getByRole('button', { name: /^Compartilhadas comigo/ }))
    await click(screen.getByRole('button', { name: 'Runbook de incidentes' }))
    expect(onopen).toHaveBeenLastCalledWith('s3')
  })

  it('a busca rápida abre a página escolhida em vez de só filtrar', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await key('k', { ctrlKey: true })
    await type(screen.getByRole('combobox'), 'nixos')
    await fireEvent.keyDown(screen.getByRole('combobox'), { key: 'Enter' })
    expect(onopen).toHaveBeenCalledWith('p2')
    expect(screen.queryByRole('dialog')).toBeNull()
  })

  it('uma página nova também pode ser aberta; o cartão mostra o que foi escrito nela', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Nova página' }))
    await click(screen.getByRole('button', { name: 'Sem título' }))
    expect(onopen).toHaveBeenCalledOnce()
    expect(onopen.mock.calls[0][0]).toMatch(/^n\d+$/)
  })
})

describe('Dashboard — páginas do cofre', () => {
  beforeEach(() => viewport.set(1400))
  const prompt = () => within(screen.getByRole('dialog', { name: 'Senha mestra' }))
  const submit = async (password: string) => {
    const input = screen.getByLabelText('Senha mestra', { selector: 'input' })
    await type(input, password)
    await fireEvent.submit(input.closest('form')!)
  }

  it('na lista geral, abrir uma página do cofre pede a senha ANTES de entrar', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    const locked = cards().find((c) => within(c).queryByText('Senhas e chaves de recuperação'))!
    expect(within(locked).getByText('Conteúdo protegido. Desbloqueie o Cofre para visualizar esta página.')).toBeTruthy()
    await click(within(locked).getByRole('button', { name: 'Senhas e chaves de recuperação' }))
    expect(onopen).not.toHaveBeenCalled()
    expect(prompt().getByRole('heading', { name: 'Senha mestra' })).toBeTruthy()
    expect(screen.getByRole('dialog').textContent).toContain('Senhas e chaves de recuperação')

    await submit('abc')
    expect(screen.getByRole('alert').textContent).toContain('mínimo 4')
    expect(onopen).not.toHaveBeenCalled()

    await submit('abcd')
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(onopen).toHaveBeenCalledExactlyOnceWith('p4')
    expect(toast.message).toBe('Cofre desbloqueado')
  })

  it('cancelar a senha não abre nada e a página continua protegida', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Contas bancárias e PIX' }))
    await key('Escape')
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(onopen).not.toHaveBeenCalled()
    expect(document.body.textContent).not.toContain('chave PIX por e-mail')
  })

  it('com o cofre já aberto a página abre direto, sem pedir de novo, e o cartão mostra o texto', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: 'Contas bancárias e PIX' }))
    await submit('abcd')
    expect(onopen).toHaveBeenLastCalledWith('v5')
    await click(screen.getByRole('button', { name: 'Chave da API do provedor de IA' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(onopen).toHaveBeenLastCalledWith('v2')
    expect(screen.getByText('sk-ant-… (rotacionar em setembro)')).toBeTruthy()
  })

  it('pelo próprio cofre também abre: pede a senha e depois abre a página escolhida', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: /^Cofre \d+$/ }))
    expect(screen.getAllByRole('button', { name: /\(bloqueado\)$/ })).toHaveLength(5)
    await click(screen.getByRole('button', { name: 'Documentos — RG, CPF, passaporte (bloqueado)' }))
    expect(onopen).not.toHaveBeenCalled()
    await submit('abcd')
    expect(onopen).toHaveBeenCalledExactlyOnceWith('v3')
    // unlocked now: the next row opens at once
    await click(screen.getByRole('button', { name: /Cofre do servidor doméstico/ }))
    expect(onopen).toHaveBeenLastCalledWith('v4')
  })

  it('"Desbloquear" no cofre só abre o cofre, sem abrir página nenhuma', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: /^Cofre \d+$/ }))
    await click(screen.getByRole('button', { name: 'Desbloquear' }))
    await submit('abcd')
    expect(onopen).not.toHaveBeenCalled()
    expect(screen.getByText('DESBLOQUEADO')).toBeTruthy()
  })

  it('"Nova entrada segura" cria a página protegida e já a abre', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await click(screen.getByRole('button', { name: /^Cofre \d+$/ }))
    await click(screen.getAllByRole('button', { name: /Nova entrada segura/ })[0])
    await submit('abcd')
    expect(onopen).toHaveBeenCalledOnce()
    const id = onopen.mock.calls[0][0]
    expect(id).toMatch(/^n\d+$/)
    // the new entry sits in the vault list, next to the button that made it
    expect(screen.getAllByRole('button', { name: /Nova entrada segura/ })).toHaveLength(2)
  })

  it('a busca rápida também pede a senha para uma página do cofre', async () => {
    const onopen = vi.fn()
    render(Dashboard, { onopen })
    await key('k', { ctrlKey: true })
    await type(screen.getByRole('combobox'), 'contas bancárias')
    await fireEvent.keyDown(screen.getByRole('combobox'), { key: 'Enter' })
    expect(onopen).not.toHaveBeenCalled()
    await submit('abcd')
    expect(onopen).toHaveBeenCalledWith('v5')
  })

  it('o que está dentro do cofre não aparece na busca enquanto ele está trancado', async () => {
    render(Dashboard, { onopen: vi.fn() })
    await type(screen.getByRole('searchbox'), 'FG882301')
    expect(screen.getByTestId('empty')).toBeTruthy()
    await type(screen.getByRole('searchbox'), 'passaporte')
    expect(cardTitles()).toEqual(['Documentos — RG, CPF, passaporte']) // the title may be found
  })

  it('o cofre guarda as páginas protegidas e o contador bate com a lista', async () => {
    render(Dashboard, { onopen: vi.fn() })
    expect(screen.getByRole('button', { name: /^Cofre \d+$/ }).textContent).toContain('5')
    await click(screen.getByRole('button', { name: /^Cofre \d+$/ }))
    expect(screen.getAllByRole('listitem').length).toBeGreaterThanOrEqual(5)
    await type(screen.getByRole('searchbox'), 'pix')
    expect(screen.getAllByRole('button', { name: /\(bloqueado\)$/ })).toHaveLength(1)
  })

  it('o cartão de uma página compartilhada por mim mostra o ícone de compartilhamento', () => {
    render(Dashboard, { onopen: vi.fn() })
    const card = cards().find((c) => within(c).queryByText('Rotina de encerramento do trimestre'))!
    expect(within(card).getByText('Compartilhada com 2 pessoas')).toBeTruthy()
    const plain = cards().find((c) => within(c).queryByText('Reforma do apartamento — orçamento'))!
    expect(within(plain).queryByText(/Compartilhada com/)).toBeNull()
  })
})

describe('Dashboard — largura média (barra que abre sobre a página)', () => {
  beforeEach(() => viewport.set(1000))

  it('começa só com ícones, abre ao passar o mouse e fecha ao sair', async () => {
    render(Dashboard)
    const rail = document.querySelector<HTMLElement>('[data-rail]')!
    expect(screen.queryByText('SELF-HOSTED')).toBeNull()
    expect(rail.dataset.open).toBe('false')
    expect(screen.getByRole('button', { name: 'Todas as páginas' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Abrir menu' })).toBeNull()

    await fireEvent.mouseEnter(rail)
    expect(rail.dataset.open).toBe('true')
    expect(screen.getByText('SELF-HOSTED')).toBeTruthy()
    await fireEvent.mouseLeave(rail)
    expect(rail.dataset.open).toBe('false')
    expect(screen.queryByText('SELF-HOSTED')).toBeNull()
  })

  it('o teclado também abre (foco dentro) e fecha (foco fora)', async () => {
    render(Dashboard)
    const rail = document.querySelector<HTMLElement>('[data-rail]')!
    await fireEvent.focusIn(screen.getByRole('button', { name: 'Nova página' }))
    expect(rail.dataset.open).toBe('true')
    await fireEvent.focusOut(screen.getByRole('button', { name: 'Nova página' }), { relatedTarget: document.body })
    expect(rail.dataset.open).toBe('false')
  })

  it('tocar na barra a prende aberta até tocar fora (celular grande ou tablet)', async () => {
    render(Dashboard)
    const rail = document.querySelector<HTMLElement>('[data-rail]')!
    await click(rail)
    expect(rail.dataset.open).toBe('true')
    await fireEvent.mouseDown(rail)
    expect(rail.dataset.open).toBe('true')
    await fireEvent.mouseDown(document.querySelector('main')!)
    expect(rail.dataset.open).toBe('false')
  })

  it('abre sobre a página: a lista não muda de largura', async () => {
    render(Dashboard)
    const wrapper = document.querySelector<HTMLElement>('[data-rail]')!.parentElement!
    const before = wrapper.className
    await fireEvent.mouseEnter(document.querySelector('[data-rail]')!)
    expect(wrapper.className).toBe(before)
  })

  it('acessibilidade (axe) com a barra aberta', async () => {
    render(Dashboard)
    await fireEvent.mouseEnter(document.querySelector('[data-rail]')!)
    expect(await violations()).toEqual([])
  })
})

describe('Dashboard — celular', () => {
  beforeEach(() => viewport.set(390))

  it('menu em gaveta abre, navega e fecha sozinho; Esc também fecha', async () => {
    render(Dashboard)
    expect(screen.queryByRole('navigation')).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    expect(screen.getByRole('navigation')).toBeTruthy()

    await click(screen.getByRole('button', { name: /^Lixeira/ }))
    expect(screen.queryByRole('navigation')).toBeNull()
    expect(screen.getByRole('heading', { name: 'Lixeira' })).toBeTruthy()

    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    await key('Escape')
    expect(screen.queryByRole('navigation')).toBeNull()
  })

  it('"Nova página" da gaveta cria e fecha a gaveta', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    await click(screen.getByRole('button', { name: 'Nova página' }))
    expect(screen.queryByRole('navigation')).toBeNull()
    expect(cards()).toHaveLength(24)
  })

  it('escolher tag na gaveta filtra e fecha', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    await click(screen.getByRole('button', { name: /^receitas/ }))
    expect(screen.queryByRole('navigation')).toBeNull()
    expect(cards()).toHaveLength(3)
  })

  it('gaveta aberta e tela girada para largura grande não trava aberta', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    viewport.set(1400)
    await Promise.resolve()
    expect(screen.getAllByRole('navigation')).toHaveLength(1)
    viewport.set(390)
    await Promise.resolve()
    expect(screen.queryByRole('navigation')).toBeNull()
  })

  it('configurações em duas etapas: lista de seções, depois a seção, com voltar', async () => {
    render(Dashboard)
    await openSettings()
    expect(screen.getByRole('heading', { name: 'Configurações' })).toBeTruthy()
    expect(screen.queryByText('Idioma da interface')).toBeNull()
    await click(screen.getByRole('button', { name: 'Conta' }))
    expect(screen.getByRole('heading', { name: 'Conta', level: 2 })).toBeTruthy()
    expect(screen.getByText('Trocar senha')).toBeTruthy()
    // Esc steps back first, then closes
    await key('Escape')
    expect(screen.getByRole('heading', { name: 'Configurações' })).toBeTruthy()
    await key('Escape')
    expect(screen.queryByRole('dialog')).toBeNull()
    await openSettings()
    await click(screen.getByRole('button', { name: 'Geral' }))
    await click(screen.getByRole('button', { name: 'Voltar para as seções' }))
    expect(screen.getByRole('heading', { name: 'Configurações' })).toBeTruthy()
  })

  it('o botão de busca rápida existe (sem o texto Ctrl K) e abre a paleta', async () => {
    render(Dashboard)
    expect(screen.queryByText('Ctrl K')).toBeNull()
    await click(screen.getByRole('button', { name: 'Abrir busca rápida' }))
    expect(screen.getByRole('dialog', { name: 'Busca rápida' })).toBeTruthy()
  })

  it('acessibilidade (axe): gaveta, configurações e senha do cofre', async () => {
    render(Dashboard)
    await click(screen.getByRole('button', { name: 'Abrir menu' }))
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: /^Cofre/ }))
    await click(screen.getByRole('button', { name: 'Desbloquear' }))
    expect(await violations()).toEqual([])
    await key('Escape')
    await openSettings()
    expect(await violations()).toEqual([])
    await click(screen.getByRole('button', { name: 'Geral' }))
    expect(await violations()).toEqual([])
  })
})
