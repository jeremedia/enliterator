# frozen_string_literal: true

# Tracks Ollama (local LLM) API calls with specific metrics for self-hosted models
class OllamaApiCall < ApiCall
  # Common Ollama models and their characteristics
  MODEL_INFO = {
    # Llama models
    'llama3.1:405b' => { params: 405_000_000_000, context: 128_000 },
    'llama3.1:70b' => { params: 70_000_000_000, context: 128_000 },
    'llama3.1:8b' => { params: 8_000_000_000, context: 128_000 },
    'llama3:70b' => { params: 70_000_000_000, context: 8192 },
    'llama3:8b' => { params: 8_000_000_000, context: 8192 },
    'llama2:70b' => { params: 70_000_000_000, context: 4096 },
    'llama2:13b' => { params: 13_000_000_000, context: 4096 },
    'llama2:7b' => { params: 7_000_000_000, context: 4096 },
    
    # Mistral models
    'mistral:latest' => { params: 7_000_000_000, context: 32_000 },
    'mixtral:8x7b' => { params: 47_000_000_000, context: 32_000 },
    'mixtral:8x22b' => { params: 141_000_000_000, context: 64_000 },
    
    # Code models
    'codellama:70b' => { params: 70_000_000_000, context: 16_000 },
    'codellama:34b' => { params: 34_000_000_000, context: 16_000 },
    'codellama:13b' => { params: 13_000_000_000, context: 16_000 },
    'codellama:7b' => { params: 7_000_000_000, context: 16_000 },
    'deepseek-coder:33b' => { params: 33_000_000_000, context: 16_000 },
    'starcoder2:15b' => { params: 15_000_000_000, context: 16_000 },
    
    # Embedding models
    'nomic-embed-text' => { params: 137_000_000, context: 8192, type: 'embedding' },
    'mxbai-embed-large' => { params: 335_000_000, context: 512, type: 'embedding' },
    'all-minilm' => { params: 22_000_000, context: 256, type: 'embedding' },
    
    # Other models
    'phi3:medium' => { params: 14_000_000_000, context: 128_000 },
    'phi3:mini' => { params: 3_800_000_000, context: 128_000 },
    'gemma2:27b' => { params: 27_000_000_000, context: 8192 },
    'gemma2:9b' => { params: 9_000_000_000, context: 8192 },
    'qwen2:72b' => { params: 72_000_000_000, context: 32_000 },
    'qwen2:7b' => { params: 7_000_000_000, context: 32_000 }
  }.freeze
  
  # Estimated compute costs (for internal tracking)
  # Based on GPU hours or electricity costs
  COMPUTE_COSTS = {
    # Cost per 1M tokens based on model size (rough estimates)
    small: 0.001,   # < 10B params
    medium: 0.005,  # 10B - 30B params
    large: 0.010,   # 30B - 70B params
    xlarge: 0.020   # > 70B params
  }.freeze
  
  # Provider capabilities
  def self.supports_streaming?
    true
  end
  
  def self.supports_functions?
    true  # Depends on model
  end
  
  def self.supports_vision?
    false  # Most Ollama models don't support vision yet
  end
  
  def self.supports_batching?
    false  # Ollama doesn't have batch API
  end
  
  def calculate_costs!
    # Local models have no API costs, but we can track compute costs
    self.input_cost = 0
    self.output_cost = 0
    
    # Optional: Calculate estimated compute costs
    if model_used && total_tokens
      compute_cost = estimate_compute_cost
      self.total_cost = compute_cost
      
      # Store compute metrics in metadata
      self.metadata['compute_cost_estimate'] = compute_cost
      self.metadata['cost_basis'] = 'compute_estimate'
    else
      self.total_cost = 0
    end
    
    self.currency = 'USD'  # Or could be 'COMPUTE_UNITS'
  end
  
  def extract_usage_data(result)
    if result.respond_to?(:eval_count)
      # Ollama provides different metrics
      self.prompt_tokens = result.prompt_eval_count || 0
      self.completion_tokens = result.eval_count || 0
      self.total_tokens = prompt_tokens + completion_tokens
      
      # Store Ollama-specific performance metrics
      store_performance_metrics(result)
    elsif result.is_a?(Hash)
      self.prompt_tokens = result['prompt_eval_count'] || 0
      self.completion_tokens = result['eval_count'] || 0
      self.total_tokens = result['total_tokens'] || (prompt_tokens + completion_tokens)
      
      store_performance_metrics(result)
    end
    
    # Store model info
    if model_used
      model_info = MODEL_INFO[model_used] || {}
      self.metadata['model_params'] = model_info[:params]
      self.metadata['model_context'] = model_info[:context]
      self.metadata['model_type'] = model_info[:type] || 'text'
    end
  end
  
  # Ollama-specific performance metrics
  def tokens_per_second
    return 0 unless completion_tokens && metadata['eval_duration']
    
    duration_seconds = metadata['eval_duration'] / 1_000_000_000.0
    return 0 if duration_seconds == 0
    
    (completion_tokens / duration_seconds).round(2)
  end
  
  def prompt_tokens_per_second
    return 0 unless prompt_tokens && metadata['prompt_eval_duration']
    
    duration_seconds = metadata['prompt_eval_duration'] / 1_000_000_000.0
    return 0 if duration_seconds == 0
    
    (prompt_tokens / duration_seconds).round(2)
  end
  
  def model_load_time_ms
    return 0 unless metadata['load_duration']
    
    (metadata['load_duration'] / 1_000_000.0).round(2)
  end
  
  # Check if model is loaded in memory
  def model_was_loaded?
    model_load_time_ms > 100  # If load time > 100ms, model was likely loaded
  end
  
  # Performance analysis
  def self.performance_stats(period = :today)
    scope = period == :today ? today : where(created_at: period)
    
    {
      total_calls: scope.count,
      avg_tokens_per_second: scope.average("metadata->>'eval_duration'").to_f,
      avg_prompt_eval_speed: scope.average("metadata->>'prompt_eval_duration'").to_f,
      models_used: scope.distinct.pluck(:model_used),
      total_tokens_processed: scope.sum(:total_tokens),
      avg_response_time: scope.average(:response_time_ms).to_f.round(2),
      model_loads: scope.where("metadata->>'load_duration' > '100000000'").count,
      by_model: scope.group(:model_used).calculate_stats
    }
  end
  
  # Resource usage tracking
  def self.resource_usage(period = :today)
    scope = period == :today ? today : where(created_at: period)
    
    {
      total_gpu_time_ms: scope.sum(:response_time_ms).to_f,
      total_tokens: scope.sum(:total_tokens),
      peak_models: scope
        .group(:model_used)
        .sum(:total_tokens)
        .sort_by { |_, v| -v }
        .first(5),
      estimated_vram_usage: estimate_vram_usage(scope),
      estimated_compute_cost: scope.sum(:total_cost).to_f.round(4)
    }
  end
  
  private
  
  def store_performance_metrics(result)
    # Store Ollama-specific timing information (in nanoseconds)
    self.metadata.merge!({
      'load_duration' => result['load_duration'] || result.load_duration,
      'eval_duration' => result['eval_duration'] || result.eval_duration,
      'prompt_eval_duration' => result['prompt_eval_duration'] || result.prompt_eval_duration,
      'total_duration' => result['total_duration'] || result.total_duration,
      'model_loaded' => result['model'] || result.model,
      'created_at' => result['created_at'] || result.created_at,
      'done' => result['done'] || result.done,
      'done_reason' => result['done_reason'] || result.done_reason
    }.compact)
    
    # Convert nanoseconds to milliseconds for response_time_ms
    if metadata['total_duration']
      self.response_time_ms = metadata['total_duration'] / 1_000_000.0
    end
  end
  
  def estimate_compute_cost
    return 0 unless model_used && total_tokens
    
    model_info = MODEL_INFO[model_used]
    return 0 unless model_info
    
    # Determine model size category
    params = model_info[:params]
    cost_per_million = case params
                       when 0..10_000_000_000 then COMPUTE_COSTS[:small]
                       when 10_000_000_001..30_000_000_000 then COMPUTE_COSTS[:medium]
                       when 30_000_000_001..70_000_000_000 then COMPUTE_COSTS[:large]
                       else COMPUTE_COSTS[:xlarge]
                       end
    
    (total_tokens.to_f / 1_000_000) * cost_per_million
  end
  
  def self.estimate_vram_usage(scope)
    # Estimate VRAM usage based on models used
    models = scope.distinct.pluck(:model_used)
    
    models.map do |model|
      info = MODEL_INFO[model]
      next unless info
      
      # Rough estimate: 2 bytes per parameter for FP16
      vram_gb = (info[:params] * 2.0 / 1_073_741_824).round(2)
      [model, vram_gb]
    end.compact.to_h
  end
  
  # Ollama-specific error handling
  def extract_error_details(error)
    details = super
    
    # Common Ollama errors
    case error.message
    when /model.*not found/i
      details[:error_type] = 'model_not_found'
      details[:suggestion] = "Run: ollama pull #{model_used}"
    when /out of memory/i
      details[:error_type] = 'out_of_memory'
      details[:suggestion] = 'Try a smaller model or increase GPU memory'
    when /connection refused/i
      details[:error_type] = 'ollama_not_running'
      details[:suggestion] = 'Start Ollama: ollama serve'
    end
    
    details
  end
end