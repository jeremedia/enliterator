# frozen_string_literal: true

namespace :training do
  desc "Generate training questions for all EKNs"
  task generate_all: :environment do
    puts "🎯 Generating training questions for all EKNs..."
    
    total_generated = 0
    
    Ekn.find_each do |ekn|
      puts "\n📋 Processing EKN: #{ekn.name} (#{ekn.slug})"
      
      begin
        generator = TrainingQuestionGenerator.new(ekn)
        question_set = generator.generate_question_set
        
        puts "  ✅ Generated question set: #{question_set.name}"
        puts "  📊 Questions created: #{question_set.question_count}"
        puts "  🎭 Question types: #{question_set.questions_by_type.map { |type, count| "#{type}(#{count})" }.join(', ')}"
        puts "  🎯 Archetypes: #{question_set.questions_by_archetype.map { |arch, count| "#{arch}(#{count})" }.join(', ')}"
        
        total_generated += question_set.question_count
        
      rescue => e
        puts "  ❌ Failed: #{e.message}"
      end
    end
    
    puts "\n🎉 Training question generation complete!"
    puts "📊 Total questions generated: #{total_generated}"
    puts "📈 Question sets created: #{TrainingQuestionSet.count}"
  end
  
  desc "Generate training questions for specific EKN"
  task :generate, [:ekn_id] => :environment do |_task, args|
    ekn_id = args[:ekn_id]
    
    unless ekn_id
      puts "❌ Please provide an EKN ID: rails training:generate[EKN_ID]"
      exit 1
    end
    
    ekn = Ekn.find(ekn_id)
    puts "🎯 Generating training questions for EKN: #{ekn.name} (#{ekn.slug})"
    
    generator = TrainingQuestionGenerator.new(ekn)
    question_set = generator.generate_question_set
    
    puts "\n✅ Question set generated successfully!"
    puts "📋 Set Name: #{question_set.name}"
    puts "📊 Total Questions: #{question_set.question_count}"
    puts ""
    
    puts "📈 Question Distribution:"
    question_set.questions_by_type.each do |type, count|
      puts "  #{type.humanize}: #{count}"
    end
    
    puts "\n🎭 Archetype Focus:"
    question_set.questions_by_archetype.each do |archetype, count|
      puts "  #{archetype.humanize}: #{count}"
    end
    
    puts "\n📚 Difficulty Levels:"
    question_set.questions_by_difficulty.each do |level, count|
      puts "  #{level.humanize}: #{count}"
    end
    
    puts "\n🔍 Sample Questions:"
    question_set.training_questions.limit(5).each_with_index do |question, i|
      puts "  #{i+1}. [#{question.difficulty_level.upcase}] #{question.question_text}"
      puts "     Type: #{question.question_type.humanize} | Target: #{question.archetype_focus&.humanize || 'Any'}"
      puts ""
    end
  end
  
  desc "Show training question statistics"
  task stats: :environment do
    puts "📊 TRAINING QUESTIONS STATISTICS"
    puts "=" * 50
    
    total_sets = TrainingQuestionSet.count
    total_questions = TrainingQuestion.count
    active_questions = TrainingQuestion.active.count
    
    puts "Question Sets: #{total_sets}"
    puts "Total Questions: #{total_questions}"
    puts "Active Questions: #{active_questions}"
    puts ""
    
    if total_questions > 0
      puts "📈 By Question Type:"
      TrainingQuestion.group(:question_type).count.each do |type, count|
        puts "  #{type.humanize}: #{count}"
      end
      
      puts "\n🎭 By Archetype Focus:"
      TrainingQuestion.where.not(archetype_focus: nil).group(:archetype_focus).count.each do |archetype, count|
        puts "  #{archetype.humanize}: #{count}"
      end
      
      puts "\n📚 By Difficulty:"
      TrainingQuestion.group(:difficulty_level).count.each do |level, count|
        puts "  #{level.humanize}: #{count}"
      end
      
      puts "\n🎯 Performance Summary:"
      excellent = TrainingQuestion.where('avg_score > 0.9 AND times_asked > 0').count
      good = TrainingQuestion.where('avg_score > 0.7 AND avg_score <= 0.9 AND times_asked > 0').count
      needs_work = TrainingQuestion.where('avg_score <= 0.5 AND times_asked > 2').count
      untested = TrainingQuestion.where(times_asked: 0).count
      
      puts "  Excellent (>90%): #{excellent}"
      puts "  Good (70-90%): #{good}" 
      puts "  Needs Work (<50%): #{needs_work}"
      puts "  Untested: #{untested}"
    end
    
    puts "\n📋 By EKN:"
    TrainingQuestionSet.includes(:ekn).each do |set|
      puts "  #{set.ekn.slug}: #{set.question_count} questions (#{set.status})"
    end
  end
  
  desc "Show training questions for specific EKN"
  task :show, [:ekn_id] => :environment do |_task, args|
    ekn_id = args[:ekn_id]
    
    unless ekn_id
      puts "❌ Please provide an EKN ID: rails training:show[EKN_ID]"
      exit 1
    end
    
    ekn = Ekn.find(ekn_id)
    question_sets = ekn.training_question_sets
    
    if question_sets.empty?
      puts "❌ No training questions found for EKN: #{ekn.name}"
      puts "Generate questions with: rails training:generate[#{ekn.id}]"
      exit 0
    end
    
    puts "📋 TRAINING QUESTIONS FOR EKN: #{ekn.name.upcase}"
    puts "=" * 60
    
    question_sets.each do |question_set|
      puts "\n📦 Question Set: #{question_set.name}"
      puts "Status: #{question_set.status.humanize}"
      puts "Generated: #{question_set.created_at.strftime('%Y-%m-%d %H:%M')}"
      puts "Questions: #{question_set.question_count}"
      
      puts "\n📚 Questions:"
      question_set.training_questions.order(:question_type, :difficulty_level).each_with_index do |question, i|
        puts "#{(i+1).to_s.rjust(2)}. [#{question.difficulty_level.upcase[0]}][#{question.question_type[0].upcase}] #{question.question_text}"
        puts "    Target: #{question.archetype_focus&.humanize || 'Any'} | Score: #{question.avg_score.round(2)} (#{question.times_asked}x)"
        puts ""
      end
    end
  end
end