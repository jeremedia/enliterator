
# == Schema Information
#
# Table name: logs
#
#  id            :bigint           not null, primary key
#  label         :string
#  loggable_type :string           not null
#  uuid          :uuid             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  loggable_id   :bigint           not null
#
# Indexes
#
#  index_logs_on_loggable  (loggable_type,loggable_id)
#  index_logs_on_uuid      (uuid) UNIQUE
#
class Log < ApplicationRecord

  belongs_to :loggable, polymorphic: true

  has_many :log_items, -> { order(num: :desc) }, dependent: :delete_all

  def clear
    log_items.delete_all
  end

  def l(log_text, status:)
    log_items.create(text: log_text, status: status)
  end

  def log_lines
    log_items.map(&:log_line)
  end
end
