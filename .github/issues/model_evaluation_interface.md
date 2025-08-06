# Add Model Evaluation Interface for Fine-Tuned Models

## Overview
Implement a side-by-side chat interface to evaluate and compare fine-tuned models against their base models, similar to OpenAI's Playground comparison feature.

## User Story
As an admin user, I want to evaluate my fine-tuned model against the base model to understand the improvements and differences in responses, so I can validate that the fine-tuning has achieved its objectives.

## Requirements

### UI Components
1. **Entry Point**: Add "Evaluate Model" link/button on the FineTuneJob#show page (only for completed jobs)
2. **Two-Column Chat Interface**:
   - Left column: Base model (e.g., `gpt-4.1-mini-2025-04-14`)
   - Right column: Fine-tuned model (e.g., `ft:gpt-4.1-mini-2025-04-14:chds:enliterator-v20250806:C1XuVw$K`)
   - Model names displayed in header of each column
   - Visual distinction between columns (border/background)

3. **Shared Components**:
   - System prompt editor at top (collapsible)
   - Single message input at bottom
   - Send button that dispatches to both models
   - Clear conversation button
   - Export/Copy buttons for results

### Technical Architecture

#### Routes
```ruby
namespace :admin do
  resources :fine_tune_jobs do
    member do
      get :evaluate
      post :evaluate_message
    end
  end
end
```

#### Controller Actions
```ruby
# app/controllers/admin/fine_tune_jobs_controller.rb
def evaluate
  @job = FineTuneJob.find(params[:id])
  @system_prompt = load_system_prompt_for_job(@job)
  @base_model = @job.base_model
  @fine_tuned_model = @job.fine_tuned_model
end

def evaluate_message
  # Handle streaming responses from both models
end
```

#### View Structure
```erb
<!-- app/views/admin/fine_tune_jobs/evaluate.html.erb -->
<div class="evaluation-container">
  <!-- System Prompt Section -->
  <div class="system-prompt-section">
    <textarea id="system-prompt">...</textarea>
  </div>
  
  <!-- Chat Columns -->
  <div class="chat-columns">
    <div class="chat-column base-model">
      <h3><%= @base_model %></h3>
      <div class="messages"></div>
    </div>
    
    <div class="chat-column fine-tuned-model">
      <h3><%= @fine_tuned_model %></h3>
      <div class="messages"></div>
    </div>
  </div>
  
  <!-- Input Section -->
  <div class="input-section">
    <textarea id="user-message"></textarea>
    <button id="send-message">Send to Both</button>
  </div>
</div>
```

#### JavaScript/Stimulus Controller
```javascript
// app/javascript/controllers/model_evaluator_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["systemPrompt", "userMessage", "baseMessages", "fineTunedMessages"]
  
  async sendMessage() {
    const message = this.userMessageTarget.value
    const systemPrompt = this.systemPromptTarget.value
    
    // Send to both models in parallel
    const [baseResponse, fineTunedResponse] = await Promise.all([
      this.callModel(this.baseModel, systemPrompt, message),
      this.callModel(this.fineTunedModel, systemPrompt, message)
    ])
    
    // Display responses
    this.appendMessage(this.baseMessagesTarget, message, baseResponse)
    this.appendMessage(this.fineTunedMessagesTarget, message, fineTunedResponse)
  }
  
  async callModel(model, systemPrompt, message) {
    // Implement streaming response handling
  }
}
```

### Backend Services

#### Evaluation Service
```ruby
# app/services/evaluation/model_comparator.rb
module Evaluation
  class ModelComparator
    def initialize(base_model:, fine_tuned_model:, system_prompt:)
      @base_model = base_model
      @fine_tuned_model = fine_tuned_model
      @system_prompt = system_prompt
    end
    
    def evaluate(user_message)
      {
        base_response: call_openai(@base_model, user_message),
        fine_tuned_response: call_openai(@fine_tuned_model, user_message)
      }
    end
    
    private
    
    def call_openai(model, message)
      # Use OpenAI client with streaming
    end
  end
end
```

### System Prompt Management
- Load default system prompt from PromptTemplate for "enliterator_routing"
- Allow editing within the evaluation interface
- Auto-save prompt changes to session/localStorage

### Features

#### Core Features (MVP)
- [ ] Side-by-side chat interface
- [ ] Simultaneous model queries
- [ ] Message history display
- [ ] System prompt configuration
- [ ] Real-time streaming responses

#### Enhanced Features (Phase 2)
- [ ] Response time comparison metrics
- [ ] Token usage tracking
- [ ] Export conversation as JSON/Markdown
- [ ] Save evaluation sessions
- [ ] Highlight differences between responses
- [ ] Rating system for responses
- [ ] A/B test metrics collection

### Implementation Tasks

#### Phase 1: Core Interface
- [ ] Create evaluate action in controller
- [ ] Build two-column chat view layout
- [ ] Implement Stimulus controller for chat interactions
- [ ] Add OpenAI API integration for both models
- [ ] Handle streaming responses
- [ ] Add system prompt management

#### Phase 2: Functionality
- [ ] Implement message history
- [ ] Add clear conversation feature
- [ ] Build export functionality
- [ ] Add response metrics display
- [ ] Implement error handling
- [ ] Add loading states

#### Phase 3: Enhancements
- [ ] Add response difference highlighting
- [ ] Implement evaluation metrics
- [ ] Build session saving/loading
- [ ] Add keyboard shortcuts
- [ ] Implement copy-to-clipboard for responses
- [ ] Add fullscreen mode

### Testing Requirements
- [ ] Unit tests for ModelComparator service
- [ ] Controller tests for evaluate actions
- [ ] System tests for chat interface
- [ ] JavaScript tests for Stimulus controller
- [ ] Performance tests for concurrent API calls

### Security Considerations
- Ensure proper authentication/authorization
- Validate model ownership before evaluation
- Rate limiting for API calls
- Sanitize user inputs
- Secure system prompt storage

### Performance Considerations
- Stream responses instead of waiting for completion
- Cache system prompts
- Implement request debouncing
- Use background jobs for heavy processing
- Consider WebSocket for real-time updates

### Accessibility
- Keyboard navigation support
- Screen reader compatibility
- High contrast mode support
- Focus management
- ARIA labels for interactive elements

### Success Metrics
- Time to first byte for responses
- Comparison completion rate
- User satisfaction with evaluation process
- Number of evaluations per fine-tuned model
- Average evaluation session duration

## Dependencies
- OpenAI Ruby gem (>= 0.16.0)
- Stimulus.js for frontend interactivity
- Turbo Streams for real-time updates
- ActionCable (optional) for WebSocket support

## Related Issues
- #26 - Fine-Tune Dataset Builder
- #27 - Fine-Tune Trainer Service
- #47 - OpenAI Settings Management

## Acceptance Criteria
1. Admin can click "Evaluate Model" from a completed FineTuneJob
2. Two-column interface loads with base and fine-tuned models
3. System prompt is editable and applies to both models
4. Single message input sends to both models simultaneously
5. Responses stream in real-time to respective columns
6. Conversation history is maintained during session
7. User can clear conversation and start fresh
8. Error states are handled gracefully
9. Loading states show during API calls
10. Interface is responsive and mobile-friendly

## References
- [OpenAI Playground](https://platform.openai.com/playground)
- [OpenAI Fine-tuning Guide](https://platform.openai.com/docs/guides/fine-tuning)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)

---

**Priority**: High
**Effort**: Large (3-5 days)
**Type**: Feature
**Labels**: enhancement, fine-tuning, evaluation, admin-ui