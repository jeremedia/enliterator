# == Schema Information
#
# Table name: interview_sessions
#
#  id         :bigint           not null, primary key
#  session_id :string
#  data       :jsonb
#  completed  :boolean
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_interview_sessions_on_session_id  (session_id)
#
class InterviewSession < ApplicationRecord
  validates :session_id, presence: true, uniqueness: true
  
  before_save :update_completed_status
  
  scope :incomplete, -> { where(completed: false) }
  scope :complete, -> { where(completed: true) }
  scope :recent, -> { order(created_at: :desc) }
  
  def complete?
    data&.dig('state') == 'complete'
  end
  
  private
  
  def update_completed_status
    self.completed = complete?
  end
end
