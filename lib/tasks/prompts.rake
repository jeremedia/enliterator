namespace :ops do
  namespace :prompts do
    desc "Smoke test PromptTemplates for structure, variables, and token estimates (no API calls)"
    task :smoke => :environment do
      samples = {
        'Lexicon Term Extraction' => {
          content: "Vector indexes accelerate approximate nearest neighbor search over embeddings.",
          source_type: 'docs',
          metadata: '{"section":"embeddings","tags":["vector","ANN"]}'
        },
        'Entity Extraction - Ten Pool Canon' => {
          content: "We released v2.0 of the Index Builder in 2024, refining the HNSW parameters.",
          lexicon_context: '[{"term":"HNSW Index"}]',
          source_metadata: '{"release":"2.0","year":2024}'
        },
        'Relation Extraction - Verb Glossary' => {
          content: "The Idea of hybrid search codifies a Practical method that connects graph paths to vector search.",
          entities: '[{"label":"Hybrid Search","pool":"Idea"},{"label":"Hybrid Method","pool":"Practical"}]'
        },
        'Query Router' => {
          query: "Show paths connecting vector index and hybrid search",
          context: '{"user":"test"}'
        },
        'Fine-Tune System Prompt' => {
          input: "Connect embeddings to vector index and narrate the path"
        }
      }

      def print_header(title)
        puts "\n" + ('=' * 80)
        puts "🔎 #{title}"
        puts ('=' * 80)
      end

      PromptTemplate.active.order(:name).find_each do |t|
        print_header("#{t.name} (#{t.purpose}) [#{t.service_class}]")
        expected = t.expected_variables
        provided = (samples[t.name] || {}).transform_keys(&:to_s)
        validation = t.validate_variables(provided)
        puts "Expected variables: #{expected.inspect}"
        puts "Provided variables: #{provided.keys.inspect}"
        if validation[:valid]
          puts "✓ Variables: OK"
        else
          puts "✗ Missing variables: #{validation[:missing].join(', ')}"
        end

        messages = t.build_messages((provided['content'] || provided['query'] || provided['input'] || ''), provided.symbolize_keys)
        sys = messages.first[:content]
        usr = messages.last[:content]
        # Heuristics for strictness
        strict = sys.include?('STRICT OUTPUT') || sys.include?('STRICT JSON')
        puts "Strictness hint present: #{strict ? 'YES' : 'NO'}"
        # Token estimation
        est = t.test_with_sample((provided['content'] || provided['query'] || provided['input'] || ''), provided.symbolize_keys)
        puts "Estimated tokens: #{est[:estimated_tokens]} (system #{est[:system_prompt_length]}, user #{est[:user_prompt_length]})"
        # Show first 8 lines of system and 6 of user
        puts "-- system (preview) --"
        puts sys.lines.first(8).join
        puts "-- user (preview) --"
        puts usr.lines.first(6).join
      end

      puts "\nAll prompts inspected without API calls."
      puts "Tip: Set stricter validators if needed (e.g., JSON-only reminders)."
    end
  end
end

