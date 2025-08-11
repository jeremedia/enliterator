import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer"]
  static values = { conversationId: Number }
  
  connect() {
    console.log('🎯 Chat controller connected, conversation ID:', this.conversationIdValue)
    this.scrollToBottom()
    
    // Auto-scroll when new messages are added or content changes
    this.setupAutoScroll()
  }
  
  setupAutoScroll() {
    const messages = document.getElementById('messages')
    const messagesContainer = this.messagesContainerTarget
    
    if (!messages || !messagesContainer) {
      console.warn('Auto-scroll setup failed: missing elements', { messages, messagesContainer })
      return
    }
    
    // Track container height to only scroll when content actually grows
    let lastScrollHeight = messagesContainer.scrollHeight
    let scrollTimeout = null
    
    // Debounced scroll function
    const debouncedScroll = () => {
      if (scrollTimeout) clearTimeout(scrollTimeout)
      scrollTimeout = setTimeout(() => {
        const newScrollHeight = messagesContainer.scrollHeight
        
        // Only scroll if content height increased (new content added)
        if (newScrollHeight > lastScrollHeight) {
          console.log('📜 Content height increased:', lastScrollHeight, '→', newScrollHeight)
          this.scrollToBottom()
          lastScrollHeight = newScrollHeight
        }
      }, 100) // 100ms debounce
    }
    
    // Smart observer that only triggers on streaming updates
    const observer = new MutationObserver((mutations) => {
      let isStreamingUpdate = false
      
      mutations.forEach(mutation => {
        // Only scroll for specific streaming-related changes:
        
        // 1. New messages added to the messages container
        if (mutation.type === 'childList' && mutation.target === messages && mutation.addedNodes.length > 0) {
          console.log('📜 New message added - streaming update')
          isStreamingUpdate = true
        }
        
        // 2. Changes to elements with streaming-related IDs (content, trace, tools)
        else if (mutation.target && mutation.target.id) {
          const targetId = mutation.target.id
          if (targetId.includes('-content') || targetId.includes('-trace') || targetId.includes('-tools')) {
            // Check if this looks like a Turbo Stream update (not user interaction)
            const isStreamingContent = mutation.target.querySelector('[data-markdown-streaming-value="true"]') ||
                                     mutation.target.classList.contains('animate-pulse') ||
                                     (mutation.type === 'childList' && mutation.addedNodes.length > 0)
            
            if (isStreamingContent) {
              console.log('📜 Streaming content update detected in', targetId)
              isStreamingUpdate = true
            }
          }
        }
      })
      
      if (isStreamingUpdate) {
        debouncedScroll()
      }
    })
    
    // Watch messages container and immediate children only (not deep subtree)
    observer.observe(messages, { 
      childList: true,
      subtree: false  // Don't watch deep changes to avoid user interactions
    })
    
    // Also watch specific streaming target elements
    const watchStreamingElement = (selector) => {
      const elements = document.querySelectorAll(selector)
      elements.forEach(element => {
        observer.observe(element, {
          childList: true,
          subtree: false,
          characterData: false  // Don't watch text changes in streaming elements
        })
      })
    }
    
    // Watch for streaming updates to existing message content/trace/tools
    watchStreamingElement('[id$="-content"]')
    watchStreamingElement('[id$="-trace"]') 
    watchStreamingElement('[id$="-tools"]')
    
    console.log('📜 Smart auto-scroll observer set up successfully')
  }
  
  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      const container = this.messagesContainerTarget
      const oldScrollTop = container.scrollTop
      container.scrollTop = container.scrollHeight
      
      // Log scroll activity for debugging
      if (container.scrollTop !== oldScrollTop) {
        console.log(`📜 Auto-scrolled: ${oldScrollTop} → ${container.scrollTop} (height: ${container.scrollHeight})`)
      }
    }
  }
  
  copyMessage(event) {
    const messageId = event.currentTarget.dataset.messageId
    const contentEl = document.getElementById(`message-${messageId}-content`)
    
    if (contentEl) {
      const text = contentEl.textContent
      navigator.clipboard.writeText(text)
      
      // Show feedback
      const button = event.currentTarget
      const originalHTML = button.innerHTML
      button.innerHTML = '<svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>'
      
      setTimeout(() => {
        button.innerHTML = originalHTML
      }, 2000)
    }
  }

  copyCode(event) {
    const code = event.currentTarget.dataset.code
    navigator.clipboard.writeText(code)
    
    // Show feedback
    const button = event.currentTarget
    const originalHTML = button.innerHTML
    button.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
      </svg>
    `
    
    setTimeout(() => {
      button.innerHTML = originalHTML
    }, 2000)
  }
  
  copyError(event) {
    const errorDetails = JSON.parse(event.currentTarget.dataset.errorDetails)
    
    // Format error for copying - exactly what's needed for troubleshooting
    const errorText = `${errorDetails.ekn} • Error
${errorDetails.error_class}
${errorDetails.message}
${errorDetails.backtrace.join('\n')}

Message ID: ${errorDetails.message_id}
Timestamp: ${errorDetails.timestamp}`
    
    navigator.clipboard.writeText(errorText)
    
    // Show feedback
    const button = event.currentTarget
    const originalHTML = button.innerHTML
    button.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
      </svg>
      Copied!
    `
    
    setTimeout(() => {
      button.innerHTML = originalHTML
    }, 2000)
  }
  
  retryMessage(event) {
    const messageId = event.currentTarget.dataset.messageId
    
    // Submit form to retry the message
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/ekn/${this.element.dataset.eknSlug}/chat/retry`
    
    const csrfToken = document.querySelector('[name="csrf-token"]').content
    const csrfInput = document.createElement('input')
    csrfInput.type = 'hidden'
    csrfInput.name = 'authenticity_token'
    csrfInput.value = csrfToken
    
    const messageInput = document.createElement('input')
    messageInput.type = 'hidden'
    messageInput.name = 'message_id'
    messageInput.value = messageId
    
    form.appendChild(csrfInput)
    form.appendChild(messageInput)
    
    document.body.appendChild(form)
    form.submit()
    document.body.removeChild(form)
  }
  
  showExportMenu() {
    const formats = ['JSON', 'Markdown']
    const format = confirm('Export as JSON? (Cancel for Markdown)') ? 'json' : 'markdown'
    
    // Create a temporary form for export
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = `/ekn/${this.element.dataset.eknSlug}/chat/export`
    
    const csrfToken = document.querySelector('[name="csrf-token"]').content
    const csrfInput = document.createElement('input')
    csrfInput.type = 'hidden'
    csrfInput.name = 'authenticity_token'
    csrfInput.value = csrfToken
    
    const conversationInput = document.createElement('input')
    conversationInput.type = 'hidden'
    conversationInput.name = 'conversation_id'
    conversationInput.value = this.conversationIdValue
    
    const formatInput = document.createElement('input')
    formatInput.type = 'hidden'
    formatInput.name = 'format'
    formatInput.value = format
    
    form.appendChild(csrfInput)
    form.appendChild(conversationInput)
    form.appendChild(formatInput)
    
    document.body.appendChild(form)
    form.submit()
    document.body.removeChild(form)
  }
}