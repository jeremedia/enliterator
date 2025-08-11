Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  
  # Mission Control - Jobs monitoring UI
  mount MissionControl::Jobs::Engine => "/jobs"

  # Webhook endpoints
  namespace :webhooks do
    post 'openai', to: 'openai#receive'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "navigator#index"  # Changed to Knowledge Navigator as main interface
  
  # Public splash and deep overview
  get "/public", to: "public#index"
  get "/public/more", to: "public#more", as: :public_more
  
  # EKN-scoped routes (top-level)
  scope "/ekn/:ekn_slug" do
    # Main EKN pages
    get "", to: "ekns/main#show", as: :ekn  # Landing page
    get "dashboard", to: "ekns/main#dashboard", as: :ekn_dashboard  # Impressive dashboard
    get "pipeline", to: "ekns/main#pipeline", as: :ekn_pipeline  # Stage-by-stage pipeline
    get "training", to: "ekns/main#training", as: :ekn_training  # Training methodology
    get "entities/:id", to: "ekns/main#entity", as: :ekn_entity  # Entity details for popover
    
    # Knowledge Entities listing
    resources :entities, controller: 'ekns/entities', only: [:index, :show], param: :id do
      collection do
        get :search
        get :filter
      end
    end
    
    # Legacy ask interface
    get "ask", to: "navigator/ask#show", as: :ekn_ask
    get "ask/metrics", to: "navigator/ask#metrics", as: :ekn_ask_metrics
    get "ask/answer_status", to: "navigator/ask#answer_status", as: :ekn_ask_answer_status
    
    # Modern chat interface
    resources :chat, controller: 'ekns/chat', only: [:index, :show, :new] do
      member do
        get :messages
        post :send_message
      end
      collection do
        get :search
        post :export
        post :retry
        patch :update_settings
      end
    end

    # Detailed Import Stats
    resources :imports, controller: 'ekns/import_stats', only: [:index] do
      member do
        get :details
      end
    end
  end
  
  # Knowledge Navigator - The main user interface
  namespace :navigator do
    get '/', to: 'conversation#index'
    post '/converse', to: 'conversation#converse'
    post '/generate_ui', to: 'ui#generate'
    post '/modify_ui', to: 'ui#modify'
    post '/voice/transcribe', to: 'voice#transcribe'
    post '/voice/synthesize', to: 'voice#synthesize'
    get '/onboarding', to: 'onboarding#start'
    post '/create_ekn', to: 'ekn#create'
    get '/ekn/:id/explore', to: 'ekn#explore', as: :explore_ekn
    
    # Entity Cards and Edge Management (Stage 9 Vertical Slice)
    resources :entities, only: :show
    resources :edges, only: [] do
      member do
        post :promote
        post :reject
      end
    end
    
    # Legacy route redirect (within navigator namespace)
    get "ask", to: redirect { |params, request|
      ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: "completed" }).first
      "/ekn/#{ekn&.slug || 'default'}/ask"
    }
  end
  
  # Legacy welcome page (remove after transition)
  get "welcome" => "welcome#index"
  
  # Public MCP Logs (for demonstration)
  get "mcp_logs", to: "public_mcp_logs#index"
  get "mcp_logs/:id", to: "public_mcp_logs#show", as: :public_mcp_log
  
  # Admin interface
  namespace :admin do
    # Pipeline Runs monitoring
    resources :pipeline_runs, only: [:index, :show, :new, :create] do
      member do
        post :resume
        post :pause
        post :cancel
        get :logs
      end
    end
    
    # MCP Tool Calls monitoring
    resources :mcp_tool_calls, only: [:index, :show] do
      collection do
        get :recent
        get :failed
      end
    end
    
    resources :openai_settings do
      collection do
        post :test_model
        post :reset_defaults
      end
    end
    
    resources :prompt_templates do
      member do
        post :duplicate
        post :activate
        post :test
      end
    end
    
    resources :fine_tune_jobs, only: [:index, :show, :new, :create] do
      member do
        post :check_status
        post :deploy
        post :cancel
        get :evaluate
        post :evaluate_message
      end
    end
    
    resources :api_calls, only: [:index, :show] do
      member do
        post :retry
      end
      collection do
        get :export
      end
    end
    
    # EKN API Usage Analytics
    resources :ekn_usage, only: [:index, :show]
    
    # Intelligent MCP Test Runs - "Intelligence Assessing Intelligence"
    resources :mcp_intelligent_test_runs, only: [:index, :show] do
      collection do
        get :analytics
      end
    end
    
    # Admin dashboard
    get '/', to: 'dashboard#index', as: :dashboard
  end
  
  # API endpoints
  namespace :api do
    namespace :v1 do
      # MCP (Model Context Protocol) Server endpoints
      namespace :mcp do
        # Main SSE endpoint for MCP communication (ChatGPT requires /sse/ ending)
        match 'sse', to: 'mcp#sse', via: [:get, :post]
        match 'sse/', to: 'mcp#sse', via: [:get, :post]  # With trailing slash
        
        # Optional REST endpoint for testing
        post 'tools', to: 'mcp#tools'
      end
    end
  end
end
