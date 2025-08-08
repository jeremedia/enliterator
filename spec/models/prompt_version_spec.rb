# == Schema Information
#
# Table name: prompt_versions
#
#  id                :bigint           not null, primary key
#  prompt_id         :bigint           not null
#  content           :text
#  variables         :jsonb
#  status            :integer
#  version_number    :integer
#  performance_score :float
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_prompt_versions_on_prompt_id  (prompt_id)
#
require 'rails_helper'

RSpec.describe PromptVersion, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
