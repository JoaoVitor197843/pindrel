import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'
import { registerServiceWorker } from './lib/sw'

const target = document.getElementById('app')!
// the index.html skeleton goes away when the app enters (mount only appends, it does not clear the target)
target.replaceChildren()

const app = mount(App, { target })

registerServiceWorker()

export default app
