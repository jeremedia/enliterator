import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "sendButton", "charCount"]
  
  connect() {
    this.setupAutoResize()
    this.updateCharCount()
  }
  
  handleKeydown(event) {
    // Cmd/Ctrl + Enter to send
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }
  
  updateCharCount() {
    const count = this.inputTarget.value.length
    this.charCountTarget.textContent = count
    
    // Warn if approaching limit
    if (count > 3800) {
      this.charCountTarget.classList.add('text-red-500')
    } else {
      this.charCountTarget.classList.remove('text-red-500')
    }
    
    // Auto-resize
    this.autoResizeTextarea()
  }
  
  setupAutoResize() {
    this.inputTarget.addEventListener('input', () => {
      this.autoResizeTextarea()
    })
  }
  
  autoResizeTextarea() {
    const textarea = this.inputTarget
    textarea.style.height = 'auto'
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + 'px'
  }
  
  reset() {
    // Reset form after successful submission
    this.inputTarget.value = ''
    this.inputTarget.style.height = '52px'
    this.updateCharCount()
    this.inputTarget.focus()
  }
}