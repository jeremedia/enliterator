# == Schema Information
#
# Table name: prompts
#
#  id                 :bigint           not null, primary key
#  key                :string
#  name               :string
#  description        :text
#  category           :integer
#  context            :integer
#  active             :boolean
#  current_version_id :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_prompts_on_key  (key) UNIQUE
#
require 'rails_helper'

RSpec.describe Prompt, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
