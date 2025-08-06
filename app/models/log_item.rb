# == Schema Information
#
# Table name: log_items
#
#  id         :bigint           not null, primary key
#  item_data  :jsonb
#  log_label  :string
#  num        :integer
#  status     :string
#  text       :text
#  uuid       :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  log_id     :bigint           not null
#
# Indexes
#
#  index_log_items_on_log_id  (log_id)
#  index_log_items_on_uuid    (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (log_id => logs.id)
#
class LogItem < ApplicationRecord
  include ActionView::RecordIdentifier
  belongs_to :log
  positioned on: :log, column: :num

  DEFAULT_LABEL = "ITEM"
  DEFAULT_STATUS = "NO STATUS"
  DEFAULT_TEXT = "NO TEXT"
  DEFAULT_DATA = {}

  after_initialize :set_defaults, unless: :persisted?
  before_validation :set_uuid, on: :create

  after_create :broadcast_create

  def broadcast_create
    broadcast_prepend_later_to :general, inserts_by: :prepend, target: dom_id(log, :log_items), partial: "shared/log_line"
  end

  def set_defaults
    self.status ||= DEFAULT_STATUS
    self.text ||= DEFAULT_TEXT
    self.item_data ||= DEFAULT_DATA
    self.log_label ||= DEFAULT_LABEL
  end

  def log_line
    "##{self.num} - #{self.log_label} - #{self.text}"
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
