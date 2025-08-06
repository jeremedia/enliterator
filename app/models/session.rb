# app/models/session.rb
# Session model for tracking pre-auth ownership of EKNs and conversations
# This allows users to create and manage EKNs before we add authentication
class Session < ApplicationRecord
  # Associations
  has_many :ekns, dependent: :destroy
  has_many :conversations, dependent: :destroy
  
  # Validations
  validates :browser_session_id, presence: true, uniqueness: true
  
  # Find or create a session based on browser session ID
  def self.for_browser_session(session_id)
    find_or_create_by!(browser_session_id: session_id) do |session|
      session.metadata = {
        created_at: Time.current,
        user_agent: 'unknown'
      }
    end
  end
  
  # Statistics
  def total_ekns
    ekns.count
  end
  
  def active_ekns
    ekns.active.count
  end
  
  def total_knowledge_nodes
    ekns.sum(&:total_nodes)
  end
  
  # Find the Meta-Enliterator if this session owns it
  def meta_enliterator
    ekns.find_by(metadata: { is_meta: true })
  end
end