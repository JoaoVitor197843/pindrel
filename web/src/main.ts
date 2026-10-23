import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'

const target = document.getElementById('app')!
// o esqueleto do index.html some quando o app entra (mount só acrescenta, não limpa o alvo)
target.replaceChildren()

const app = mount(App, { target })

export default app
