import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

export default class extends Controller {
  static values = { 
    content: String,
    streaming: { type: Boolean, default: false }
  }
  
  connect() {
    console.log('📝 Markdown controller connected, content length:', this.contentValue?.length || 0, 'streaming:', this.streamingValue)
    this.configureMarked()
    this.render()
    
    // For streaming messages, observe DOM changes
    if (this.streamingValue) {
      this.observeStreamingUpdates()
    }
  }
  
  configureMarked() {
    // Configure marked.js with custom renderers
    const renderer = new marked.Renderer()
    
    // Custom link renderer to handle node URLs with pop-overs
    renderer.link = (token) => {
      // Extract href and text from the token object (new marked.js API)
      const href = token.href
      const text = token.text
      const title = token.title
      
      // Safety check: ensure href is a string
      if (!href || typeof href !== 'string') {
        console.warn('Invalid href in markdown link token:', token)
        return `<span class="text-red-500">[Invalid link: ${text}]</span>`
      }
      
      console.log('📝 Processing link:', href)
      
      // Detect entity URLs (pattern: /ekns/{slug}/entities/{id})  
      const entityUrlMatch = href.match(/\/ekns\/[^\/]+\/entities\/(\d+)/)
      
      if (entityUrlMatch) {
        const entityId = entityUrlMatch[1]
        return `<a href="${href}" 
                   class="text-indigo-600 hover:text-indigo-800 underline font-medium cursor-pointer"
                   data-action="click->markdown#showNodePopover:prevent"
                   data-node-id="${entityId}"
                   data-node-href="${href}"
                   title="${title || `Entity ${entityId}`}">
                  ${text}
                </a>`
      }
      
      // Also detect node URLs (pattern: /ekn/{slug}/nodes/{id})  
      const nodeUrlMatch = href.match(/\/ekn\/[^\/]+\/nodes\/(\d+)/)
      
      if (nodeUrlMatch) {
        const nodeId = nodeUrlMatch[1]
        return `<a href="${href}" 
                   class="text-indigo-600 hover:text-indigo-800 underline font-medium cursor-pointer"
                   data-action="click->markdown#showNodePopover:prevent"
                   data-node-id="${nodeId}"
                   data-node-href="${href}"
                   title="${title || `Node ${nodeId}`}">
                  ${text}
                </a>`
      }
      
      // Regular external links
      return `<a href="${href}" 
                 class="text-indigo-600 hover:text-indigo-800 underline" 
                 target="_blank" 
                 rel="noopener" 
                 title="${title || href || 'External link'}">
                ${text}
              </a>`
    }
    
    // Custom code renderer with copy buttons
    renderer.code = (code, lang) => {
      const escapedCode = this.escapeHtml(code)
      return `
        <div class="relative group my-4">
          <pre class="bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto"><code class="language-${lang || 'plaintext'}">${escapedCode}</code></pre>
          <button class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-2 bg-gray-800 rounded hover:bg-gray-700 text-gray-300"
                  data-action="click->chat#copyCode"
                  data-code="${this.escapeHtml(code)}"
                  title="Copy code">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
            </svg>
          </button>
        </div>`
    }
    
    // Configure marked with our custom renderer
    marked.setOptions({
      renderer: renderer,
      highlight: function(code, lang) {
        // Basic syntax highlighting - can be enhanced later
        return code
      },
      langPrefix: 'hljs language-',
      pedantic: false,
      gfm: true,
      breaks: false,
      sanitize: false,
      smartLists: true,
      smartypants: false,
      xhtml: false
    })
  }
  
  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
  
  contentValueChanged() {
    console.log('📝 Content changed, new length:', this.contentValue?.length || 0)
    this.render()
  }
  
  observeStreamingUpdates() {
    // Watch for Turbo Stream updates to this element
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' || mutation.type === 'characterData') {
          // Extract markdown from data attribute if present
          const streamingDiv = this.element.querySelector('.streaming-message')
          if (streamingDiv && streamingDiv.dataset.markdown) {
            this.contentValue = streamingDiv.dataset.markdown
            this.render()
          }
        }
      })
    })
    
    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      characterData: true
    })
  }
  
  render() {
    let content = this.contentValue || ''
    
    // Pre-process: Convert standalone entity URLs to proper markdown links
    // Pattern: [5275] Some Title — Pool: Idea — Description https://e.dev.domt.app/ekns/arctic-research/entities/5275
    content = content.replace(
      /(\[(\d+)\][^]*?)(\s+)(https:\/\/[^\s]+\/entities\/\2)(\s|$)/g,
      '[$1]($4)$5'
    )
    
    // Convert markdown to HTML using marked.js
    const html = marked(content)
    this.element.innerHTML = html
    console.log('📝 Rendered', content.length, 'chars →', html.length, 'HTML chars')
  }
  
  // Pop-over functionality for node links
  showNodePopover(event) {
    const nodeId = event.currentTarget.dataset.nodeId
    const nodeHref = event.currentTarget.dataset.nodeHref
    
    // TODO: Implement actual popover with node details fetched via AJAX
    // For demo purposes, show a simple alert
    alert(`🔗 Node ${nodeId}\n${nodeHref}\n\n(Pop-over with node details would appear here)`)
  }
  
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}