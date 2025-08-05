import { defineShikiSetup } from '@slidev/types'

export default defineShikiSetup(() => {
  return {
    themes: {
      dark: 'github-dark',
      light: 'github-light',
    },
    langs: [
      'ruby',
      'bash',
      'yaml',
      'json',
      'typescript',
      'javascript',
      'markdown',
      'mermaid',
    ],
  }
})