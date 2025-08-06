Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

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
  end
  
  # Legacy welcome page (remove after transition)
  get "welcome" => "welcome#index"
  
  # Pipeline Runs monitoring
  resources :pipeline_runs, only: [:index, :show, :new, :create] do
    member do
      post :resume
      post :pause
      get :logs
    end
  end
  
  # Admin interface
  namespace :admin do
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
    
    # Admin dashboard
    get '/', to: 'dashboard#index', as: :dashboard
  end
  
  # Future API endpoints for MCP server
  namespace :api do
    namespace :v1 do
      # MCP tools will go here
      # resources :mcp, only: [:create]
    end
  end
end
