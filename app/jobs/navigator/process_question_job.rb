class Navigator::ProcessQuestionJob < ApplicationJob
  queue_as :default

  def perform(ekn_slug:, question:, mode:, cache_key:)
    ekn = Ekn.find_by!(slug: ekn_slug)
    
    # Process the question
    ask_service = Navigator::AskService.new(ekn: ekn, question: question)
    answer = ask_service.call
    
    # Store in cache with 1 hour expiry
    Rails.cache.write(cache_key, answer, expires_in: 1.hour)
    
    answer
  rescue => e
    Rails.logger.error "Error processing question: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Store error in cache so client knows it failed
    error_response = {
      error: true,
      message: "Failed to process question: #{e.message}",
      fallback: "Unable to process your question at this time. Please try again."
    }
    Rails.cache.write(cache_key, error_response, expires_in: 5.minutes)
    
    raise e
  end
end