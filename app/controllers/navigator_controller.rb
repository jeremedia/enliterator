# The main Knowledge Navigator interface - Stage 9 of the Enliterator pipeline
# This transforms technical infrastructure into a conversational experience
class NavigatorController < ApplicationController
  def index
    # The main Knowledge Navigator interface
    # This is where users experience the magic - not JSON, not admin panels, but natural conversation
    @conversation_id = session[:conversation_id] ||= SecureRandom.uuid
    @current_ekn = current_user_ekn
    
    # Load graph statistics if we have an EKN
    if @current_ekn
      graph_service = Graph::QueryService.new(@current_ekn.id)
      @graph_stats = graph_service.get_statistics
      
      # Set the current EKN in session
      session[:current_ekn_id] ||= @current_ekn.id
    end
    
    # Check if this is a first-time visitor
    @is_first_visit = !cookies[:navigator_visited]
    cookies[:navigator_visited] = { value: true, expires: 1.year.from_now }
    
    # Load conversation history if exists
    @conversation_history = load_conversation_history
    
    # Set the personality and tone for the Knowledge Navigator
    @navigator_personality = {
      name: "Enliterator Navigator",
      greeting: first_time_greeting || returning_greeting,
      voice: "conversational",
      expertise: "transforming data into Knowledge Navigators"
    }
  end
  
  private
  
  def first_time_greeting
    return nil unless @is_first_visit
    
    [
      "Welcome! I'm your Enliterator Knowledge Navigator. I help transform data into conversational experiences like this one. Would you like to see how I work, or do you have data you'd like to explore?",
      "Hello! I'm here to help you create Knowledge Navigators from your data. Think of me as a guide who can transform any collection of documents into an interactive, conversational experience. How can I help you today?",
      "Welcome to Enliterator! I transform data collections into Knowledge Navigators - conversational interfaces that understand your data deeply. Would you like to create one from your own data, or explore how it works?"
    ].sample
  end
  
  def returning_greeting
    if @current_ekn
      time_based_greeting + " I'm connected to the #{@current_ekn.name.split('_').first(2).join(' ').capitalize} Knowledge Navigator with #{@current_ekn.literacy_score}/100 literacy score. What would you like to explore?"
    else
      time_based_greeting + " " + continuation_prompt
    end
  end
  
  def time_based_greeting
    hour = Time.current.hour
    case hour
    when 5..11
      "Good morning!"
    when 12..17
      "Good afternoon!"
    when 18..22
      "Good evening!"
    else
      "Welcome back!"
    end
  end
  
  def continuation_prompt
    if @current_ekn
      "Ready to continue exploring your #{@current_ekn.name} Knowledge Navigator?"
    else
      "Ready to create your first Knowledge Navigator?"
    end
  end
  
  def load_conversation_history
    # In production, this would load from database
    # For now, using session storage
    session[:conversation_history] || []
  end
  
  def current_user_ekn
    # Returns the user's most recent EKN or the one they're currently working with
    # For now, using the Meta-EKN (Enliterator's own Knowledge Navigator)
    @current_user_ekn ||= IngestBatch.find_by(id: session[:current_ekn_id]) || 
                          IngestBatch.where(status: 'completed')
                                     .where.not(literacy_score: nil)
                                     .order(literacy_score: :desc)
                                     .first
  end
  
  def user_signed_in?
    # Placeholder for user authentication
    # Will integrate with actual auth system
    false
  end
end