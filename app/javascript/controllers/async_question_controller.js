import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["answerContainer", "loadingSpinner"]
  static values = { 
    jobId: String,
    cacheKey: String,
    eknSlug: String,
    pollInterval: { type: Number, default: 1000 }
  }

  connect() {
    if (this.jobIdValue && this.cacheKeyValue) {
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.showLoading()
    this.pollTimer = setInterval(() => {
      this.checkAnswer()
    }, this.pollIntervalValue)
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  async checkAnswer() {
    try {
      const response = await fetch(`/ekn/${this.eknSlugValue}/ask/answer_status?job_id=${this.jobIdValue}&cache_key=${encodeURIComponent(this.cacheKeyValue)}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      
      if (data.ready) {
        this.stopPolling()
        this.hideLoading()
        this.renderAnswer(data.answer)
      } else if (data.status === 'failed') {
        this.stopPolling()
        this.hideLoading()
        this.showError(data.message || 'Question processing failed')
      }
      // Continue polling if still processing
      
    } catch (error) {
      console.error('Error checking answer status:', error)
      this.stopPolling()
      this.hideLoading()
      this.showError('Failed to check answer status. Please refresh the page.')
    }
  }

  showLoading() {
    if (this.hasLoadingSpinnerTarget) {
      this.loadingSpinnerTarget.classList.remove("hidden")
    }
    
    if (this.hasAnswerContainerTarget) {
      this.answerContainerTarget.innerHTML = `
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-6">
          <div class="flex items-center">
            <svg class="animate-spin h-5 w-5 text-blue-600 mr-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <div>
              <p class="text-sm font-medium text-blue-900">Processing your question...</p>
              <p class="text-xs text-blue-700 mt-1">This may take a few moments while we search the knowledge graph.</p>
            </div>
          </div>
        </div>
      `
    }
  }

  hideLoading() {
    if (this.hasLoadingSpinnerTarget) {
      this.loadingSpinnerTarget.classList.add("hidden")
    }
  }

  renderAnswer(answer) {
    if (!this.hasAnswerContainerTarget) return
    
    let html = ''
    
    if (answer.error) {
      this.showError(answer.message || 'An error occurred')
      return
    }
    
    // AI Generated Answer
    if (answer.answer) {
      html += `
        <div class="border-l-4 border-blue-400 bg-blue-50 p-4 mb-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-blue-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-blue-800">AI Answer</h3>
              <div class="mt-2 text-sm text-blue-700 whitespace-pre-wrap">${this.escapeHtml(answer.answer)}</div>
            </div>
          </div>
        </div>
      `
    }
    
    // Path Sentence
    if (answer.path_sentence) {
      html += `
        <div class="border-l-4 border-green-400 bg-green-50 p-4 mb-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-green-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-green-800">Path Found</h3>
              <div class="mt-2 text-sm text-green-700">
                <p class="font-semibold">Path Sentence:</p>
                <p class="mt-1">${this.escapeHtml(answer.path_sentence)}</p>
              </div>
            </div>
          </div>
        </div>
      `
    } else if (answer.fallback) {
      html += `
        <div class="border-l-4 border-yellow-400 bg-yellow-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-yellow-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-yellow-800">No Path Found</h3>
              <div class="mt-2 text-sm text-yellow-700">
                <p>${this.escapeHtml(answer.fallback)}</p>
              </div>
            </div>
          </div>
        </div>
      `
    }
    
    // Citations
    if (answer.citations && answer.citations.length > 0) {
      html += `
        <div class="bg-gray-50 rounded-lg p-4 mb-4">
          <h3 class="text-sm font-medium text-gray-900 mb-2">Citations</h3>
          <ul class="space-y-2">
      `
      
      answer.citations.forEach((citation, i) => {
        html += `
          <li class="text-sm">
            <span class="font-medium">[${i + 1}]</span>
            Item ${citation.item_id}:
            <span class="italic">"${this.escapeHtml(citation.snippet)}"</span>
          </li>
        `
      })
      
      html += '</ul></div>'
    }
    
    // Rights Echo
    if (answer.rights_echo) {
      const re = answer.rights_echo
      html += `
        <div class="bg-blue-50 rounded-lg p-4">
          <h3 class="text-sm font-medium text-blue-900 mb-2">Rights Echo</h3>
          <ul class="text-sm text-blue-700">
            <li>Publishability: ${re.publishability || 'unknown'}</li>
            <li>Training Eligible: ${re.training_eligibility || 'unknown'}</li>
            ${re.license ? `<li>License: ${this.escapeHtml(re.license)}</li>` : ''}
            ${re.attribution ? `<li>Attribution: ${this.escapeHtml(re.attribution)}</li>` : ''}
          </ul>
        </div>
      `
    }
    
    this.answerContainerTarget.innerHTML = html
  }

  showError(message) {
    if (this.hasAnswerContainerTarget) {
      this.answerContainerTarget.innerHTML = `
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-red-700">${this.escapeHtml(message)}</p>
            </div>
          </div>
        </div>
      `
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}