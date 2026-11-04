import { render, screen } from '@testing-library/svelte'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { selection } from '../../stores/servers.svelte'
import SecureNotice from './SecureNotice.svelte'

const realLocation = window.location
afterEach(() => {
  vi.stubGlobal('location', realLocation)
  selection.tlsOffered = false
})

const on = (protocol: string) => vi.stubGlobal('location', { ...realLocation, protocol })

describe('SecureNotice', () => {
  it('em https diz que a conexão é segura', () => {
    on('https:')
    render(SecureNotice)
    expect(screen.getByTestId('secure-notice').textContent).toContain('Conexão segura (HTTPS)')
    expect(screen.queryByTestId('insecure-notice')).toBeNull()
  })

  it('em http, com lado seguro disponível, avisa e leva à página de conexão', () => {
    on('http:')
    selection.tlsOffered = true
    render(SecureNotice)
    expect(screen.getByTestId('insecure-notice').textContent).toContain('não é criptografada')
    expect(screen.getByRole('link', { name: 'Conectar com segurança' }).getAttribute('href')).toBe('/server/connect/')
  })

  it('em http, sem lado seguro, não incomoda ninguém', () => {
    on('http:')
    render(SecureNotice)
    expect(screen.queryByTestId('secure-notice')).toBeNull()
    expect(screen.queryByTestId('insecure-notice')).toBeNull()
  })
})
