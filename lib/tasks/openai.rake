namespace :ops do
  namespace :openai do
    desc "Probe OpenAI SDK: list models, test responses, test batches (safe limits)"
    task :probe, [:model] => :environment do |_, args|
      begin
        client = OPENAI
        model = args[:model] || OpenaiSetting.get('model_extraction') || Rails.application.config.openai[:extraction_model]
        puts "Using model: #{model}"

        puts "\nListing first 10 models..."
        begin
          models = client.models.list
          names = Array(models.respond_to?(:data) ? models.data : models)
                    .map { |m| m.respond_to?(:id) ? m.id : (m[:id] || m['id'] rescue m.to_s) }
          puts names.first(10).inspect
        rescue => e
          puts "Models.list error: #{e.message}"
          # Fallback: make a raw request to avoid typed Page mapping/middleware issues
          begin
            raw = client.request(method: :get, path: 'models')
            ids = Array(raw[:data] || raw['data']).map { |m| m[:id] || m['id'] }.compact
            puts "Models (raw): #{ids.first(10).inspect}"
          rescue => ee
            puts "Models raw request error: #{ee.message}"
          end
        end

        puts "\nTesting Responses API minimal call..."
        begin
          resp = client.responses.create(model: model, input: 'Return JSON: {"ok":true}')
          usage = resp.respond_to?(:usage) ? resp.usage : nil
          if usage
            puts "Response usage: input=#{usage.input_tokens} output=#{usage.output_tokens} total=#{usage.total_tokens}"
          end
          out = resp.respond_to?(:output_text) ? resp.output_text : resp.to_s
          puts "Output: #{out}"
        rescue => e
          puts "Responses.create error: #{e.message}"
          # Fallback to chat.completions for sanity
          begin
            chat = client.chat.completions.create(model: model, messages: [{ role: 'user', content: 'Say ok' }])
            txt = if chat.respond_to?(:choices) && chat.choices.first.respond_to?(:message)
                    chat.choices.first.message.content
                  else
                    chat.to_s
                  end
            puts "Chat.completions fallback OK: #{txt}"
          rescue => ee
            puts "Chat.completions error: #{ee.message}"
          end
        end

        puts "\nChecking Batches capability..."
        if defined?(OpenAI::Resources::Batches)
          puts "Batches resource defined in gem; skipping list to avoid hangs in older SDKs"
        else
          puts "Batches resource not present in this gem version"
        end
      rescue => e
        puts "ERROR: #{e.class}: #{e.message}"
      end
    end
  end
end
