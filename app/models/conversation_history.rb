# == Schema Information
#
# Table name: conversation_histories
#
#  id              :bigint           not null, primary key
#  conversation_id :string
#  user_id         :string
#  role            :string
#  content         :text
#  metadata        :jsonb
#  position        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_conversation_histories_on_conversation_id  (conversation_id)
#
class ConversationHistory < ApplicationRecord
  # Store conversation messages in database to avoid cookie overflow
  validates :conversation_id, presence: true
  validates :role, inclusion: { in: %w[user assistant system] }
  validates :content, presence: true
  
  scope :for_conversation, ->(conv_id) { where(conversation_id: conv_id).order(:position) }
  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
  
  # Auto-increment position within conversation
  before_create :set_position
  
  # Clean up old conversations
  def self.cleanup_old_conversations(days_ago = 7)
    where('created_at < ?', days_ago.days.ago).destroy_all
  end
  
  private
  
  def set_position
    max_position = ConversationHistory
      .where(conversation_id: conversation_id)
      .maximum(:position) || 0
    self.position = max_position + 1
  end
end
