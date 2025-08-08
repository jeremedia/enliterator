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
