import { Controller } from "@hotwired/stimulus"

// The Knowledge Navigator JavaScript controller
// This brings the conversational interface to life, handling user interactions,
// dynamic UI generation, and voice capabilities

export default class extends Controller {
  static targets = ["input", "messages", "form", "dynamicUI", "typingIndicator", "voiceToggle", "voiceInput"]
  
  connect() {
    console.log("Knowledge Navigator connected - Stage 9 active!")
    
    this.conversationId = this.element.dataset.conversationId
    this.voiceEnabled = false
    this.isProcessing = false
    
    // Initialize voice capabilities if available
    this.initializeVoice()
    
    // Set up event listeners
    this.setupEventListeners()
    
    // Auto-resize textarea
    this.setupTextareaResize()
    
    // Initialize suggestion chips
    this.initializeSuggestions()
  }
  
  setupEventListeners() {
    // Form submission
    if (this.hasFormTarget) {
      this.formTarget.addEventListener('submit', this.handleSubmit.bind(this))
    }
    
    // Voice toggle
    if (this.hasVoiceToggleTarget) {
      this.voiceToggleTarget.addEventListener('click', this.toggleVoice.bind(this))
    }
    
    // Voice input button
    if (this.hasVoiceInputTarget) {
      this.voiceInputTarget.addEventListener('click', this.startVoiceInput.bind(this))
    }
    
    // File drag and drop
    this.setupFileDragDrop()
  }
  
  async handleSubmit(event) {
    event.preventDefault()
    
    if (this.isProcessing) return
    
    const message = this.inputTarget.value.trim()
    if (!message) return
    
    // Add user message to UI
    this.addMessage('user', message)
    
    // Clear input and show typing indicator
    this.inputTarget.value = ''
    this.showTypingIndicator()
    this.isProcessing = true
    
    try {
      // Send to conversation endpoint
      const response = await this.sendMessage(message)
      
      // Hide typing indicator
      this.hideTypingIndicator()
      
      // Add assistant response
      this.addMessage('assistant', response.message)
      
      // Generate UI if specified
      if (response.ui_spec) {
        this.generateDynamicUI(response.ui_spec)
      }
      
      // Create visualization if generated
      if (response.visualization) {
        this.createVisualization(response.visualization)
      }
      
      // Play voice if enabled
      if (this.voiceEnabled && response.voice_url) {
        this.playVoice(response.voice_url)
      }
      
      // Show suggestions
      if (response.suggestions) {
        this.showSuggestions(response.suggestions)
      }
      
    } catch (error) {
      console.error('Conversation error:', error)
      this.hideTypingIndicator()
      this.addMessage('assistant', "I encountered an issue. Could you try rephrasing that?")
    } finally {
      this.isProcessing = false
    }
  }
  
  async sendMessage(message) {
    const response = await fetch('/navigator/converse', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        message: message,
        conversation_id: this.conversationId,
        voice_enabled: this.voiceEnabled
      })
    })
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }
    
    return await response.json()
  }
  
  addMessage(role, content) {
    const messagesContainer = this.messagesTarget
    const messageDiv = document.createElement('div')
    messageDiv.className = `message ${role}-message flex items-start space-x-3`
    
    const avatarHtml = role === 'assistant' 
      ? `<div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex-shrink-0 flex items-center justify-center">
           <span class="text-white text-sm font-bold">E</span>
         </div>`
      : `<div class="w-8 h-8 bg-slate-200 rounded-full flex-shrink-0"></div>`
    
    const bgClass = role === 'assistant' 
      ? 'bg-gradient-to-br from-blue-50 to-purple-50' 
      : 'bg-slate-100'
    
    messageDiv.innerHTML = `
      ${avatarHtml}
      <div class="flex-1">
        <div class="${bgClass} rounded-2xl px-4 py-3 max-w-3xl">
          <p class="text-slate-800">${this.escapeHtml(content)}</p>
        </div>
      </div>
    `
    
    messagesContainer.appendChild(messageDiv)
    
    // Smooth scroll to bottom
    messagesContainer.scrollTop = messagesContainer.scrollHeight
  }
  
  generateDynamicUI(uiSpec) {
    // This is where we generate dynamic visualizations
    const container = document.getElementById('dynamic-ui-container')
    if (!container) return
    
    // Show the container
    container.classList.remove('hidden')
    
    // Clear previous UI
    container.innerHTML = ''
    
    // Create the appropriate UI component based on spec
    const component = this.createUIComponent(uiSpec)
    container.appendChild(component)
    
    // Animate in
    requestAnimationFrame(() => {
      component.classList.add('animate-in')
    })
  }
  
  createUIComponent(spec) {
    const wrapper = document.createElement('div')
    wrapper.className = 'bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-4 transition-all opacity-0 transform scale-95'
    
    switch(spec.component) {
      case 'timeline':
        wrapper.innerHTML = this.createTimelineComponent(spec)
        break
      case 'network-graph':
        wrapper.innerHTML = this.createNetworkGraphComponent(spec)
        break
      case 'map':
        wrapper.innerHTML = this.createMapComponent(spec)
        break
      case 'comparison-chart':
        wrapper.innerHTML = this.createComparisonChartComponent(spec)
        break
      case 'data-table':
        wrapper.innerHTML = this.createDataTableComponent(spec)
        break
      default:
        wrapper.innerHTML = '<p>Visualization coming soon...</p>'
    }
    
    // Add animation class after a tick
    setTimeout(() => {
      wrapper.classList.remove('opacity-0', 'scale-95')
      wrapper.classList.add('opacity-100', 'scale-100')
    }, 10)
    
    return wrapper
  }
  
  createTimelineComponent(spec) {
    return `
      <div class="timeline-component">
        <h3 class="font-semibold text-slate-900 mb-4">Evolution Timeline</h3>
        <div class="relative">
          <div class="absolute left-4 top-0 bottom-0 w-0.5 bg-slate-200"></div>
          <div class="space-y-4">
            <!-- Timeline items would be generated here -->
            <div class="relative flex items-center">
              <div class="absolute left-4 w-2 h-2 bg-blue-500 rounded-full -translate-x-1/2"></div>
              <div class="ml-10 bg-slate-50 rounded-lg p-3">
                <p class="text-sm text-slate-600">Timeline visualization will show your data evolution...</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    `
  }
  
  createNetworkGraphComponent(spec) {
    return `
      <div class="network-graph-component">
        <h3 class="font-semibold text-slate-900 mb-4">Knowledge Network</h3>
        <div class="bg-slate-50 rounded-lg p-8 text-center">
          <svg class="w-16 h-16 text-slate-400 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
          </svg>
          <p class="text-sm text-slate-600">Interactive network graph will appear here...</p>
        </div>
      </div>
    `
  }
  
  createMapComponent(spec) {
    return `
      <div class="map-component">
        <h3 class="font-semibold text-slate-900 mb-4">Spatial View</h3>
        <div class="bg-slate-50 rounded-lg p-8 text-center">
          <svg class="w-16 h-16 text-slate-400 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <p class="text-sm text-slate-600">Map visualization will display spatial data...</p>
        </div>
      </div>
    `
  }
  
  createComparisonChartComponent(spec) {
    return `
      <div class="comparison-chart-component">
        <h3 class="font-semibold text-slate-900 mb-4">Comparison Analysis</h3>
        <div class="grid grid-cols-2 gap-4">
          <div class="bg-slate-50 rounded-lg p-4">
            <h4 class="text-sm font-medium text-slate-700 mb-2">Before</h4>
            <div class="h-32 bg-slate-100 rounded"></div>
          </div>
          <div class="bg-slate-50 rounded-lg p-4">
            <h4 class="text-sm font-medium text-slate-700 mb-2">After</h4>
            <div class="h-32 bg-slate-100 rounded"></div>
          </div>
        </div>
      </div>
    `
  }
  
  createVisualization(visualization) {
    // Send visualization request to the visualization manager
    if (window.visualizationManager) {
      window.dispatchEvent(new CustomEvent('create-visualization', {
        detail: visualization
      }))
    } else {
      console.warn('Visualization manager not loaded yet')
      // Try again after a short delay
      setTimeout(() => {
        if (window.visualizationManager) {
          window.dispatchEvent(new CustomEvent('create-visualization', {
            detail: visualization
          }))
        }
      }, 500)
    }
  }
  
  createDataTableComponent(spec) {
    return `
      <div class="data-table-component">
        <h3 class="font-semibold text-slate-900 mb-4">Data Explorer</h3>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-slate-200">
            <thead class="bg-slate-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">Entity</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">Connections</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-slate-200">
              <tr>
                <td class="px-6 py-4 text-sm text-slate-600">Your data will appear here...</td>
                <td class="px-6 py-4 text-sm text-slate-600">—</td>
                <td class="px-6 py-4 text-sm text-slate-600">—</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    `
  }
  
  showSuggestions(suggestions) {
    const lastMessage = this.messagesTarget.lastElementChild
    if (!lastMessage) return
    
    const suggestionsDiv = document.createElement('div')
    suggestionsDiv.className = 'mt-3 flex flex-wrap gap-2 ml-11'
    
    suggestions.forEach(suggestion => {
      const chip = document.createElement('button')
      chip.className = 'suggestion-chip px-3 py-1.5 bg-white border border-slate-300 rounded-full text-sm text-slate-700 hover:bg-slate-50 transition-colors'
      chip.textContent = suggestion
      chip.addEventListener('click', () => {
        this.inputTarget.value = suggestion
        this.handleSubmit(new Event('submit'))
      })
      suggestionsDiv.appendChild(chip)
    })
    
    lastMessage.appendChild(suggestionsDiv)
  }
  
  initializeSuggestions() {
    document.querySelectorAll('.suggestion-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        this.inputTarget.value = chip.textContent
        this.handleSubmit(new Event('submit'))
      })
    })
  }
  
  // Voice capabilities
  initializeVoice() {
    if ('webkitSpeechRecognition' in window || 'SpeechRecognition' in window) {
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
      this.recognition = new SpeechRecognition()
      this.recognition.continuous = false
      this.recognition.interimResults = true
      this.recognition.lang = 'en-US'
      
      this.recognition.onresult = (event) => {
        const transcript = Array.from(event.results)
          .map(result => result[0].transcript)
          .join('')
        
        this.inputTarget.value = transcript
        
        if (event.results[0].isFinal) {
          this.handleSubmit(new Event('submit'))
        }
      }
      
      this.recognition.onerror = (event) => {
        console.error('Speech recognition error:', event.error)
        this.addMessage('assistant', "I couldn't understand that. Could you try typing instead?")
      }
    }
    
    // Check for speech synthesis
    this.speechSynthesis = window.speechSynthesis
  }
  
  toggleVoice() {
    this.voiceEnabled = !this.voiceEnabled
    
    if (this.hasVoiceToggleTarget) {
      this.voiceToggleTarget.classList.toggle('bg-blue-100')
      this.voiceToggleTarget.classList.toggle('text-blue-600')
    }
    
    if (this.voiceEnabled) {
      this.addMessage('assistant', "Voice interaction enabled. Click the microphone to speak, or I'll read my responses aloud.")
    } else {
      this.addMessage('assistant', "Voice interaction disabled.")
    }
  }
  
  startVoiceInput() {
    if (!this.recognition) {
      this.addMessage('assistant', "Voice input is not available in your browser. Please type your message instead.")
      return
    }
    
    this.recognition.start()
    
    if (this.hasVoiceInputTarget) {
      this.voiceInputTarget.classList.add('animate-pulse', 'text-red-500')
    }
    
    this.recognition.onend = () => {
      if (this.hasVoiceInputTarget) {
        this.voiceInputTarget.classList.remove('animate-pulse', 'text-red-500')
      }
    }
  }
  
  useSuggestion(event) {
    // Handle clicking on suggestion chips
    const suggestion = event.target.textContent.trim()
    if (suggestion) {
      this.inputTarget.value = suggestion
      this.handleSubmit(new Event('submit'))
    }
  }
  
  playVoice(text) {
    if (!this.speechSynthesis || !this.voiceEnabled) return
    
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = 1.0
    utterance.pitch = 1.0
    utterance.volume = 0.9
    
    // Select a pleasant voice if available
    const voices = this.speechSynthesis.getVoices()
    const preferredVoice = voices.find(voice => voice.name.includes('Samantha') || voice.name.includes('Alex'))
    if (preferredVoice) {
      utterance.voice = preferredVoice
    }
    
    this.speechSynthesis.speak(utterance)
  }
  
  // File handling
  setupFileDragDrop() {
    const dropZone = this.element
    
    dropZone.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.stopPropagation()
      dropZone.classList.add('bg-blue-50')
    })
    
    dropZone.addEventListener('dragleave', (e) => {
      e.preventDefault()
      e.stopPropagation()
      dropZone.classList.remove('bg-blue-50')
    })
    
    dropZone.addEventListener('drop', (e) => {
      e.preventDefault()
      e.stopPropagation()
      dropZone.classList.remove('bg-blue-50')
      
      const files = Array.from(e.dataTransfer.files)
      if (files.length > 0) {
        this.handleFileUpload(files)
      }
    })
  }
  
  handleFileUpload(files) {
    const fileNames = files.map(f => f.name).join(', ')
    this.addMessage('user', `I'd like to create a Knowledge Navigator from these files: ${fileNames}`)
    this.addMessage('assistant', "Excellent! I'll process these files through the enliteration pipeline to create your Knowledge Navigator. This will take a few moments...")
    
    // Show pipeline status
    this.showPipelineStatus()
    
    // TODO: Actually upload files and start pipeline
  }
  
  showPipelineStatus() {
    const statusPanel = document.getElementById('pipeline-status')
    if (statusPanel) {
      statusPanel.classList.remove('hidden')
      // TODO: Update with actual pipeline stages
    }
  }
  
  // UI helpers
  showTypingIndicator() {
    const indicator = document.getElementById('typing-indicator')
    if (indicator) {
      indicator.classList.remove('hidden')
    }
  }
  
  hideTypingIndicator() {
    const indicator = document.getElementById('typing-indicator')
    if (indicator) {
      indicator.classList.add('hidden')
    }
  }
  
  setupTextareaResize() {
    if (!this.hasInputTarget) return
    
    this.inputTarget.addEventListener('input', () => {
      this.inputTarget.style.height = 'auto'
      this.inputTarget.style.height = Math.min(this.inputTarget.scrollHeight, 120) + 'px'
    })
  }
  
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}