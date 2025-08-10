import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    content: String,
    streaming: { type: Boolean, default: false }
  }
  
  connect() {
    this.render()
    
    // For streaming messages, observe DOM changes
    if (this.streamingValue) {
      this.observeStreamingUpdates()
    }
  }
  
  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
  
  contentValueChanged() {
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
    // Convert markdown to HTML
    const html = this.parseMarkdown(this.contentValue || '')
    this.element.innerHTML = html
    
    // Apply syntax highlighting to code blocks
    this.highlightCode()
  }
  
  parseMarkdown(text) {
    // Basic markdown parsing (can be enhanced with a library like marked.js)
    let html = text
    
    // Escape HTML
    html = this.escapeHtml(html)
    
    // Code blocks with syntax highlighting
    html = html.replace(/```(\w+)?\n([\s\S]*?)```/g, (match, lang, code) => {
      return `<pre><code class="language-${lang || 'plaintext'}">${this.escapeHtml(code.trim())}</code></pre>`
    })
    
    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>')
    
    // Bold
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    html = html.replace(/__([^_]+)__/g, '<strong>$1</strong>')
    
    // Italic
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>')
    html = html.replace(/_([^_]+)_/g, '<em>$1</em>')
    
    // Headers
    html = html.replace(/^### (.+)$/gm, '<h3 class="text-lg font-semibold mt-4 mb-2">$1</h3>')
    html = html.replace(/^## (.+)$/gm, '<h2 class="text-xl font-semibold mt-4 mb-2">$1</h2>')
    html = html.replace(/^# (.+)$/gm, '<h1 class="text-2xl font-bold mt-4 mb-2">$1</h1>')
    
    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="text-indigo-600 hover:text-indigo-800 underline" target="_blank">$1</a>')
    
    // Lists
    html = html.replace(/^\* (.+)$/gm, '<li class="ml-4">• $1</li>')
    html = html.replace(/^\d+\. (.+)$/gm, '<li class="ml-4">$1</li>')
    
    // Wrap consecutive list items
    html = html.replace(/(<li[^>]*>.*<\/li>\n?)+/g, (match) => {
      return `<ul class="my-2">${match}</ul>`
    })
    
    // Blockquotes
    html = html.replace(/^> (.+)$/gm, '<blockquote class="border-l-4 border-gray-300 pl-4 italic my-2">$1</blockquote>')
    
    // Horizontal rules
    html = html.replace(/^---$/gm, '<hr class="my-4 border-gray-300">')
    
    // Line breaks
    html = html.replace(/\n\n/g, '</p><p class="mb-2">')
    
    // Wrap in paragraphs
    if (!html.startsWith('<')) {
      html = `<p class="mb-2">${html}</p>`
    }
    
    return html
  }
  
  highlightCode() {
    // Find all code blocks
    const codeBlocks = this.element.querySelectorAll('pre code')
    
    codeBlocks.forEach(block => {
      // Apply basic syntax highlighting
      let code = block.textContent
      const lang = block.className.replace('language-', '')
      
      if (lang === 'javascript' || lang === 'js') {
        code = this.highlightJavaScript(code)
      } else if (lang === 'ruby' || lang === 'rb') {
        code = this.highlightRuby(code)
      } else if (lang === 'python' || lang === 'py') {
        code = this.highlightPython(code)
      } else if (lang === 'html' || lang === 'erb') {
        code = this.highlightHTML(code)
      } else if (lang === 'css') {
        code = this.highlightCSS(code)
      } else if (lang === 'json') {
        code = this.highlightJSON(code)
      }
      
      block.innerHTML = code
      
      // Add copy button
      this.addCopyButton(block.parentElement)
    })
    
    // Style inline code
    const inlineCode = this.element.querySelectorAll('code.inline-code')
    inlineCode.forEach(code => {
      code.classList.add('bg-gray-100', 'px-1', 'py-0.5', 'rounded', 'text-sm', 'font-mono')
    })
  }
  
  highlightJavaScript(code) {
    // Keywords
    code = code.replace(/\b(const|let|var|function|return|if|else|for|while|class|extends|import|export|from|async|await|try|catch|throw|new|this)\b/g, 
      '<span class="text-purple-600 font-semibold">$1</span>')
    
    // Strings
    code = code.replace(/(["'])([^"']*)\1/g, '<span class="text-green-600">$1$2$1</span>')
    
    // Numbers
    code = code.replace(/\b(\d+)\b/g, '<span class="text-blue-600">$1</span>')
    
    // Comments
    code = code.replace(/(\/\/[^\n]*)/g, '<span class="text-gray-500 italic">$1</span>')
    
    return code
  }
  
  highlightRuby(code) {
    // Keywords
    code = code.replace(/\b(def|class|module|if|elsif|else|end|do|while|for|return|yield|require|include|attr_accessor|attr_reader|attr_writer)\b/g, 
      '<span class="text-purple-600 font-semibold">$1</span>')
    
    // Strings
    code = code.replace(/(["'])([^"']*)\1/g, '<span class="text-green-600">$1$2$1</span>')
    
    // Symbols
    code = code.replace(/(:\w+)/g, '<span class="text-orange-600">$1</span>')
    
    // Comments
    code = code.replace(/(#[^\n]*)/g, '<span class="text-gray-500 italic">$1</span>')
    
    return code
  }
  
  highlightPython(code) {
    // Keywords
    code = code.replace(/\b(def|class|if|elif|else|for|while|return|import|from|as|try|except|with|lambda|pass|break|continue)\b/g, 
      '<span class="text-purple-600 font-semibold">$1</span>')
    
    // Strings
    code = code.replace(/(["'])([^"']*)\1/g, '<span class="text-green-600">$1$2$1</span>')
    
    // Numbers
    code = code.replace(/\b(\d+)\b/g, '<span class="text-blue-600">$1</span>')
    
    // Comments
    code = code.replace(/(#[^\n]*)/g, '<span class="text-gray-500 italic">$1</span>')
    
    return code
  }
  
  highlightHTML(code) {
    // Tags
    code = code.replace(/(&lt;\/?)(\w+)([^&]*?)(&gt;)/g, 
      '$1<span class="text-blue-600">$2</span>$3$4')
    
    // Attributes
    code = code.replace(/(\w+)=/g, '<span class="text-purple-600">$1</span>=')
    
    // Strings
    code = code.replace(/(["'])([^"']*)\1/g, '<span class="text-green-600">$1$2$1</span>')
    
    return code
  }
  
  highlightCSS(code) {
    // Selectors
    code = code.replace(/([.#]?\w+[\w-]*)\s*{/g, '<span class="text-purple-600">$1</span> {')
    
    // Properties
    code = code.replace(/(\w+-?\w*)\s*:/g, '<span class="text-blue-600">$1</span>:')
    
    // Values
    code = code.replace(/:\s*([^;]+);/g, ': <span class="text-green-600">$1</span>;')
    
    return code
  }
  
  highlightJSON(code) {
    // Keys
    code = code.replace(/"(\w+)":/g, '<span class="text-blue-600">"$1"</span>:')
    
    // String values
    code = code.replace(/:\s*"([^"]*)"/g, ': <span class="text-green-600">"$1"</span>')
    
    // Numbers
    code = code.replace(/:\s*(\d+)/g, ': <span class="text-orange-600">$1</span>')
    
    // Booleans and null
    code = code.replace(/:\s*(true|false|null)/g, ': <span class="text-purple-600">$1</span>')
    
    return code
  }
  
  addCopyButton(pre) {
    // Add container for positioning
    pre.style.position = 'relative'
    
    // Create copy button
    const button = document.createElement('button')
    button.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
      </svg>
    `
    button.className = 'absolute top-2 right-2 p-2 bg-gray-700 text-white rounded hover:bg-gray-600 transition-colors'
    button.title = 'Copy code'
    
    // Add click handler
    button.addEventListener('click', () => {
      const code = pre.querySelector('code').textContent
      navigator.clipboard.writeText(code)
      
      // Show feedback
      button.innerHTML = `
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>
      `
      
      setTimeout(() => {
        button.innerHTML = `
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
          </svg>
        `
      }, 2000)
    })
    
    pre.appendChild(button)
    
    // Style the pre element
    pre.classList.add('bg-gray-900', 'text-gray-100', 'p-4', 'rounded-lg', 'overflow-x-auto', 'my-2')
  }
  
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}