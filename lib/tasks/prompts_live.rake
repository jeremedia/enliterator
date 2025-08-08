namespace :ops do
  namespace :prompts do
    desc "Live JSON validation of extraction/router prompts via Responses API (usage: bin/rails ops:prompts:validate_live[model,yes])"
    task :validate_live, [:model, :spend] => :environment do |_, args|
      spend = args[:spend].to_s.downcase
      unless spend == 'yes' || ENV['CONFIRM_SPEND'] == 'true'
        puts "Refusing to spend tokens. Pass spend=yes or set CONFIRM_SPEND=true."
        exit 1
      end

      client = OPENAI
      model = (args[:model] || OpenaiSetting.get('model_extraction') || Rails.application.config.openai[:extraction_model])
      puts "Using model: #{model}"

      tests = [
        {
          name: 'Lexicon Term Extraction',
          variables: { content: 'Vector indexes accelerate ANN over embeddings.', source_type: 'docs', metadata: '{"section":"embeddings"}' },
          schema: {
            type: 'object',
            properties: {
              terms: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    term: { type: 'string' },
                    surface_forms: { type: 'array', items: { type: 'string' } },
                    negative_surface_forms: { type: 'array', items: { type: 'string' } },
                    canonical_description: { type: 'string' },
                    confidence: { type: 'number' }
                  },
                  required: %w[term surface_forms canonical_description confidence],
                  additionalProperties: true
                }
              }
            },
            required: %w[terms],
            additionalProperties: false
          }
        },
        {
          name: 'Entity Extraction - Ten Pool Canon',
          variables: { content: 'Released Index Builder v2.0 in 2024 refining HNSW.', lexicon_context: '[]', source_metadata: '{"release":"2.0"}' },
          schema: {
            type: 'object',
            properties: {
              entities: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    pool: { type: 'string' },
                    label: { type: 'string' },
                    repr_text: { type: 'string' },
                    confidence: { type: 'number' }
                  },
                  required: %w[pool label repr_text confidence],
                  additionalProperties: true
                }
              }
            },
            required: %w[entities],
            additionalProperties: false
          }
        },
        {
          name: 'Relation Extraction - Verb Glossary',
          variables: { content: 'Hybrid search codifies a practical method.', entities: '[{"label":"Hybrid Search","pool":"Idea"}]' },
          schema: {
            type: 'object',
            properties: {
              relations: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    verb: { type: 'string' },
                    confidence: { type: 'number' }
                  },
                  required: %w[verb confidence],
                  additionalProperties: true
                }
              }
            },
            required: %w[relations],
            additionalProperties: false
          }
        },
        {
          name: 'Query Router',
          variables: { query: 'Show paths connecting vector index and hybrid search', context: '{"user":"test"}' },
          schema: {
            type: 'object',
            properties: {
              normalized_query: { type: 'string' },
              tool: { type: 'string' },
              params: { type: 'object' },
              confidence: { type: 'number' },
              rationale: { type: 'string' }
            },
            required: %w[normalized_query tool params confidence],
            additionalProperties: true
          }
        }
      ]

      failures = 0

      tests.each do |tst|
        tpl = PromptTemplate.find_by(name: tst[:name])
        unless tpl
          puts "Missing template: #{tst[:name]}"
          failures += 1
          next
        end

        messages = tpl.build_messages((tst[:variables][:content] || tst[:variables][:query] || tst[:variables][:input] || ''), tst[:variables])
        begin
          resp = client.responses.create(
            model: model,
            input: messages.map { |m| { role: m[:role], content: m[:content] } },
            text: {
              format: {
                type: :json_schema,
                name: "Validation",
                strict: true,
                schema: tst[:schema]
              }
            }
          )
          usage = resp.usage rescue nil
          out = (resp.respond_to?(:output_text) ? resp.output_text : resp.to_s)
          parsed = nil
          begin
            parsed = JSON.parse(out)
            ok = true
          rescue JSON::ParserError
            ok = false
          end
          puts "\n[#{tst[:name]}] OK=#{ok} tokens=#{usage && usage.total_tokens}"
          unless ok
            failures += 1
            puts "Output (truncated): #{out.to_s[0, 400]}"
          end
        rescue => e
          failures += 1
          puts "[#{tst[:name]}] ERROR: #{e.class}: #{e.message}"
        end
      end

      if failures.zero?
        puts "\nAll live validations passed."
      else
        puts "\n#{failures} validation(s) failed."
        exit 2
      end
    end
  end
end
