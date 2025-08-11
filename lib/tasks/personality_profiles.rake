# frozen_string_literal: true

namespace :personality do
  desc "Generate personality profiles for all EKNs"
  task generate_all: :environment do
    puts "🎭 Generating personality profiles for all EKNs..."
    
    result = PersonalityProfileGenerator.generate_all_profiles
    
    puts "\n📊 Profile Generation Results:"
    puts "  Total EKNs processed: #{result[:total_processed]}"
    puts "  New profiles created: #{result[:generated]}"
    puts "  Existing profiles updated: #{result[:updated]}"
    puts "  Failed generations: #{result[:failed]}"
    
    if result[:failed] > 0
      puts "\n⚠️  Some profiles failed to generate. Check logs for details."
    else
      puts "\n✅ All personality profiles generated successfully!"
    end
    
    # Show summary of created profiles
    puts "\n🎭 Current Personality Profiles:"
    EknPersonalityProfile.includes(:ekn).each do |profile|
      puts "  #{profile.ekn.slug}: #{profile.base_archetype&.humanize || 'No archetype'} (v#{profile.personality_version})"
    end
  end
  
  desc "Generate personality profile for a specific EKN"
  task :generate, [:ekn_id] => :environment do |_task, args|
    ekn_id = args[:ekn_id]
    
    unless ekn_id
      puts "❌ Please provide an EKN ID: rails personality:generate[EKN_ID]"
      exit 1
    end
    
    ekn = Ekn.find(ekn_id)
    puts "🎭 Generating personality profile for EKN #{ekn.id} (#{ekn.slug})..."
    
    generator = PersonalityProfileGenerator.new(ekn)
    result = generator.generate_or_update_profile
    
    puts "\n✅ Profile #{result[:created] ? 'created' : 'updated'} successfully!"
    puts "   Archetype: #{result[:archetype].to_s.humanize}"
    puts "   Ready for chat: #{result[:profile].ready_for_chat? ? 'Yes' : 'No'}"
    
    if result[:profile].ready_for_chat?
      puts "\n🚀 This EKN is ready for personality-aware conversations!"
    else
      puts "\n⚠️  This EKN may need additional personality configuration."
    end
  end
  
  desc "Show personality profile summary for all EKNs"
  task summary: :environment do
    puts "🎭 EKN Personality Profile Summary\n"
    
    if EknPersonalityProfile.count.zero?
      puts "❌ No personality profiles found. Run 'rails personality:generate_all' first."
      exit 0
    end
    
    EknPersonalityProfile.includes(:ekn).each do |profile|
      puts "📋 #{profile.ekn.slug} (EKN ##{profile.ekn.id})"
      puts "   Archetype: #{profile.base_archetype&.humanize || 'Not set'}"
      puts "   Description: #{profile.archetype_description}"
      puts "   Ready for chat: #{profile.ready_for_chat? ? '✅' : '❌'}"
      puts "   Preferred tools: #{profile.preferred_mcp_tools.keys.join(', ')}"
      puts "   Communication style: #{profile.communication_style['tone'] || 'Not defined'}"
      puts "   Version: v#{profile.personality_version}"
      puts ""
    end
    
    # Show archetype distribution
    archetype_counts = EknPersonalityProfile.group(:base_archetype).count
    puts "🎯 Archetype Distribution:"
    archetype_counts.each do |archetype, count|
      puts "   #{archetype&.humanize || 'Unassigned'}: #{count}"
    end
  end
  
  desc "Test personality profile functionality for specific EKN"
  task :test, [:ekn_id] => :environment do |_task, args|
    ekn_id = args[:ekn_id]
    
    unless ekn_id
      puts "❌ Please provide an EKN ID: rails personality:test[EKN_ID]"
      exit 1
    end
    
    ekn = Ekn.find(ekn_id)
    profile = ekn.ekn_personality_profile
    
    unless profile
      puts "❌ No personality profile found for EKN #{ekn.id}. Run 'rails personality:generate[#{ekn.id}]' first."
      exit 1
    end
    
    puts "🧪 Testing personality profile for EKN #{ekn.id} (#{ekn.slug})\n"
    
    puts "📊 Personality Summary:"
    puts profile.personality_summary.to_yaml
    
    puts "\n📝 Evaluation Context:"
    puts profile.evaluation_context
    
    puts "\n🎯 System Prompt Elements:"
    puts profile.system_prompt_elements.to_yaml
    
    puts "\n✅ Personality profile test completed!"
  end
end