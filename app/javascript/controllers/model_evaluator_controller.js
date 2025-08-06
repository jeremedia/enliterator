import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "systemPrompt",
    "userMessage", 
    "baseMessages",
    "fineTunedMessages",
    "sendButton",
    "temperature",
    "baseStatus",
    "fineTunedStatus",
    "baseMetrics",
    "fineTunedMetrics"
  ]
  
  static values = {
    jobId: Number,
    baseModel: String,
    fineTunedModel: String
  }
  
  connect() {
    console.log("Model evaluator connected", {
      jobId: this.jobIdValue,
      baseModel: this.baseModelValue,
      fineTunedModel: this.fineTunedModelValue
    })
    
    // Initialize conversation history
    this.conversationHistory = []
    
    // Focus on message input
    this.userMessageTarget.focus()
  }
  
  async sendMessage(event) {
    event?.preventDefault()
    
    const message = this.userMessageTarget.value.trim()
    if (!message) return
    
    const systemPrompt = this.systemPromptTarget.value.trim()
    const temperature = parseFloat(this.temperatureTarget.value)
    
    // Disable send button and input
    this.setSending(true)
    
    // Add user message to both columns
    this.addUserMessage(message)
    
    // Clear input
    this.userMessageTarget.value = ""
    
    // Add loading indicators
    const baseLoadingEl = this.addLoadingMessage(this.baseMessagesTarget)
    const fineTunedLoadingEl = this.addLoadingMessage(this.fineTunedMessagesTarget)
    
    // Update status
    this.baseStatusTarget.textContent = "Generating..."
    this.fineTunedStatusTarget.textContent = "Generating..."
    
    try {
      // Make API call
      const response = await fetch(`/admin/fine_tune_jobs/${this.jobIdValue}/evaluate_message`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          message: message,
          system_prompt: systemPrompt,
          temperature: temperature
        })
      })
      
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Request failed')
      }
      
      const data = await response.json()
      
      // Remove loading indicators
      baseLoadingEl.remove()
      fineTunedLoadingEl.remove()
      
      // Add responses
      this.addAssistantMessage(
        this.baseMessagesTarget,
        data.base_response.content || data.base_response.error,
        data.base_response.error ? 'error' : 'success',
        data.metrics?.base_time,
        data.base_response.usage
      )
      
      this.addAssistantMessage(
        this.fineTunedMessagesTarget,
        data.fine_tuned_response.content || data.fine_tuned_response.error,
        data.fine_tuned_response.error ? 'error' : 'success',
        data.metrics?.fine_tuned_time,
        data.fine_tuned_response.usage
      )
      
      // Update metrics
      if (data.metrics) {
        this.updateMetrics(data.metrics)
      }
      
      // Store in conversation history
      this.conversationHistory.push({
        user: message,
        base_response: data.base_response,
        fine_tuned_response: data.fine_tuned_response,
        metrics: data.metrics,
        timestamp: new Date()
      })
      
    } catch (error) {
      console.error("Evaluation error:", error)
      
      // Remove loading indicators
      baseLoadingEl.remove()
      fineTunedLoadingEl.remove()
      
      // Show error messages
      this.addErrorMessage(this.baseMessagesTarget, error.message)
      this.addErrorMessage(this.fineTunedMessagesTarget, error.message)
      
    } finally {
      // Re-enable controls
      this.setSending(false)
      
      // Update status
      this.baseStatusTarget.textContent = "Ready"
      this.fineTunedStatusTarget.textContent = "Ready"
      
      // Focus back on input
      this.userMessageTarget.focus()
    }
  }
  
  clearConversation(event) {
    event?.preventDefault()
    
    if (!confirm("Clear all messages? This cannot be undone.")) return
    
    // Clear message areas
    this.baseMessagesTarget.innerHTML = `
      <div class="text-gray-400 text-sm text-center py-8">
        No messages yet. Start a conversation below.
      </div>
    `
    
    this.fineTunedMessagesTarget.innerHTML = `
      <div class="text-gray-400 text-sm text-center py-8">
        No messages yet. Start a conversation below.
      </div>
    `
    
    // Clear metrics
    this.baseMetricsTarget.textContent = ""
    this.fineTunedMetricsTarget.textContent = ""
    
    // Clear history
    this.conversationHistory = []
    
    // Focus on input
    this.userMessageTarget.focus()
  }
  
  exportConversation(event) {
    event?.preventDefault()
    
    if (this.conversationHistory.length === 0) {
      alert("No conversation to export")
      return
    }
    
    const exportData = {
      job_id: this.jobIdValue,
      base_model: this.baseModelValue,
      fine_tuned_model: this.fineTunedModelValue,
      system_prompt: this.systemPromptTarget.value,
      conversation: this.conversationHistory,
      exported_at: new Date().toISOString()
    }
    
    // Create download
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `evaluation_${this.jobIdValue}_${Date.now()}.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }
  
  copyMessage(event) {
    event?.preventDefault()
    
    const messageContent = event.target.closest('.flex-1').querySelector('.message-content').textContent
    
    navigator.clipboard.writeText(messageContent).then(() => {
      const originalText = event.target.textContent
      event.target.textContent = "Copied!"
      setTimeout(() => {
        event.target.textContent = originalText
      }, 2000)
    })
  }
  
  // Helper methods
  
  addUserMessage(message) {
    const template = document.getElementById('user-message-template')
    
    // Add to base column
    const baseClone = template.content.cloneNode(true)
    baseClone.querySelector('.message-content').textContent = message
    this.removeEmptyState(this.baseMessagesTarget)
    this.baseMessagesTarget.appendChild(baseClone)
    
    // Add to fine-tuned column
    const fineTunedClone = template.content.cloneNode(true)
    fineTunedClone.querySelector('.message-content').textContent = message
    this.removeEmptyState(this.fineTunedMessagesTarget)
    this.fineTunedMessagesTarget.appendChild(fineTunedClone)
    
    // Scroll to bottom
    this.scrollToBottom(this.baseMessagesTarget)
    this.scrollToBottom(this.fineTunedMessagesTarget)
  }
  
  addAssistantMessage(container, content, status = 'success', timeTaken = null, usage = null) {
    const template = document.getElementById('assistant-message-template')
    const clone = template.content.cloneNode(true)
    
    clone.querySelector('.message-content').textContent = content
    
    if (timeTaken) {
      clone.querySelector('.response-time').textContent = `${timeTaken}s`
    }
    
    if (usage && usage.total_tokens) {
      clone.querySelector('.token-count').textContent = `${usage.total_tokens} tokens`
    }
    
    if (status === 'error') {
      const messageDiv = clone.querySelector('.bg-blue-50')
      messageDiv.classList.remove('bg-blue-50')
      messageDiv.classList.add('bg-red-50', 'border', 'border-red-200')
    }
    
    container.appendChild(clone)
    this.scrollToBottom(container)
  }
  
  addLoadingMessage(container) {
    const template = document.getElementById('loading-message-template')
    const clone = template.content.cloneNode(true)
    const div = document.createElement('div')
    div.appendChild(clone)
    container.appendChild(div.firstElementChild)
    this.scrollToBottom(container)
    return container.lastElementChild
  }
  
  addErrorMessage(container, message) {
    const template = document.getElementById('error-message-template')
    const clone = template.content.cloneNode(true)
    clone.querySelector('.error-content').textContent = message
    container.appendChild(clone)
    this.scrollToBottom(container)
  }
  
  removeEmptyState(container) {
    const emptyState = container.querySelector('.text-gray-400.text-center')
    if (emptyState) {
      emptyState.remove()
    }
  }
  
  scrollToBottom(container) {
    container.scrollTop = container.scrollHeight
  }
  
  setSending(sending) {
    this.sendButtonTarget.disabled = sending
    this.userMessageTarget.disabled = sending
    
    if (sending) {
      this.sendButtonTarget.textContent = "Sending..."
    } else {
      this.sendButtonTarget.textContent = "Send to Both"
    }
  }
  
  updateMetrics(metrics) {
    if (metrics.base_time && metrics.base_tokens) {
      this.baseMetricsTarget.textContent = `${metrics.base_time}s • ${metrics.base_tokens.total_tokens} tokens`
    }
    
    if (metrics.fine_tuned_time && metrics.fine_tuned_tokens) {
      this.fineTunedMetricsTarget.textContent = `${metrics.fine_tuned_time}s • ${metrics.fine_tuned_tokens.total_tokens} tokens`
    }
  }
  
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}