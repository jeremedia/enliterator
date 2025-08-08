# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  name                   :string
#  admin                  :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  
  # Associations
  has_many :api_calls, dependent: :nullify
  
  # Validations
  validates :name, presence: true
  
  # Scopes
  scope :admins, -> { where(admin: true) }
  
  # Instance methods
  def display_name
    name.presence || email.split('@').first
  end
  
  def total_api_cost
    api_calls.sum(:total_cost)
  end
  
  def api_calls_today
    api_calls.today
  end
  
  def api_calls_this_month
    api_calls.this_month
  end
end
