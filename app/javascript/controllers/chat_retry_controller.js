import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    conversationId: Number,
    messageId: Number
  }
  
  retry(event) {
    event.preventDefault()
    
    // Disable the button
    const button = event.currentTarget
    button.disabled = true
    button.textContent = 'Retrying...'
    
    // Remove the error message
    const messageElement = document.getElementById(`message-${this.messageIdValue}`)
    if (messageElement) {
      messageElement.remove()
    }
    
    // Re-enqueue the job
    this.retryJob()
  }
  
  async retryJob() {
    try {
      const response = await fetch(`/ekn/meta-enliterator/chat/${this.conversationIdValue}/retry_message`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          message_id: this.messageIdValue
        })
      })
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      // The response will be handled by Turbo Streams
    } catch (error) {
      console.error('Failed to retry message:', error)
      // Re-enable the button if it fails
      const button = this.element.querySelector('button')
      if (button) {
        button.disabled = false
        button.textContent = 'Retry'
      }
    }
  }
}