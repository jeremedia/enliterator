import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer"]
  static values = { conversationId: Number }
  
  connect() {
    this.scrollToBottom()
    
    // Auto-scroll when new messages are added
    const observer = new MutationObserver(() => {
      this.scrollToBottom()
    })
    
    const messages = document.getElementById('messages')
    if (messages) {
      observer.observe(messages, { childList: true })
    }
  }
  
  scrollToBottom() {
    if (this.hasMessagesContainerTarget) {
      this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
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