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
          # Get the actual underlying OpenAI client to bypass tracking
          actual_client = if client.respond_to?(:client)
            # It's a tracked client, get the underlying client
            client.instance_variable_get(:@client)
          else
            # It's already the raw client
            client
          end
          
          # Now use the actual client directly
          models_response = actual_client.models.list
          
          # Extract and sort models
          if models_response.respond_to?(:data)
            model_list = models_response.data
            
            # Sort by created timestamp (newest first)
            sorted_models = model_list.sort_by { |m| -(m.created || 0) }
            
            puts "Models found: #{sorted_models.length}"
            puts "\nNewest 10 models (sorted by creation date):"
            sorted_models.first(10).each do |model|
              created_time = model.created ? Time.at(model.created).strftime("%Y-%m-%d %H:%M") : "unknown"
              puts "  #{model.id.ljust(30)} created: #{created_time}"
            end
            
            # Also show just the names for quick reference
            names = sorted_models.map { |m| m.respond_to?(:id) ? m.id : m.to_s }
            puts "\nModel IDs only:"
            puts names.first(10).inspect
          else
            # Fallback to treating it as enumerable
            names = models_response.map { |m| m.respond_to?(:id) ? m.id : m.to_s }
            puts "Models found: #{names.length}"
            puts names.first(10).inspect
          end
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

        puts "\nChecking Batch API capability..."
        begin
          # Check if Batch API is available
          if client.respond_to?(:batches)
            puts "✓ Batch API is available in the client"
            
            # Try to list existing batches (with a limit to be safe)
            begin
              # Get the actual client if it's wrapped
              actual_client = if client.respond_to?(:client)
                client.instance_variable_get(:@client)
              else
                client
              end
              
              # List recent batches
              batches = actual_client.batches.list(limit: 5)
              
              if batches.respond_to?(:data)
                batch_list = batches.data
                puts "  Found #{batch_list.length} recent batch(es)"
                
                if batch_list.any?
                  puts "\n  Recent batches:"
                  batch_list.each do |batch|
                    created_time = batch.created_at ? Time.at(batch.created_at).strftime("%Y-%m-%d %H:%M") : "unknown"
                    status = batch.status.to_s.ljust(12)
                    batch_id = batch.id.to_s[0..20]
                    puts "    ID: #{batch_id}... Status: #{status} Created: #{created_time}"
                  end
                else
                  puts "  No batches found (this is normal if you haven't used the Batch API yet)"
                end
              else
                puts "  Batch list returned but couldn't parse structure"
              end
              
              # Show batch API pricing info
              puts "\n  Batch API benefits:"
              puts "    - 50% discount on API costs"
              puts "    - Process large volumes asynchronously"
              puts "    - 24-hour completion window"
              puts "    - Ideal for embeddings, evaluations, and bulk processing"
              
            rescue => e
              puts "  Could not list batches: #{e.message}"
              puts "  This might be a permissions issue or the Batch API might not be enabled for your account"
            end
          else
            puts "✗ Batch API not available in this client configuration"
            puts "  The gem may need updating or the client needs reconfiguration"
          end
        rescue => e
          puts "Error checking Batch API: #{e.message}"
        end
      rescue => e
        puts "ERROR: #{e.class}: #{e.message}"
      end
    end
  end
end
