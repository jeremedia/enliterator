import { defineMermaidSetup } from '@slidev/types'

export default defineMermaidSetup(() => {
  return {
    theme: 'dark',
    themeVariables: {
      primaryColor: '#667eea',
      primaryTextColor: '#fff',
      primaryBorderColor: '#764ba2',
      lineColor: '#667eea',
      secondaryColor: '#764ba2',
      tertiaryColor: '#f093fb',
      background: '#1a202c',
      mainBkg: '#2d3748',
      secondBkg: '#4a5568',
      fontFamily: 'ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont',
    },
  }
})