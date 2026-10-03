import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { restoreSession } from './data/auth'
import './index.css'

// Live: who is signed in comes from the server before the first screen.
void restoreSession().then(() =>
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  ),
)
