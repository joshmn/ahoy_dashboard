AhoyDashboard::Engine.routes.draw do
  root "dashboards#show"
  resource :dashboard, only: :show do
    scope module: :dashboards do
      resource :summary, only: :show
    end
  end
  resource :styleguide, only: :show if Rails.env.development? || Rails.env.test?
  resources :assets, only: :show, param: :path, path: "assets/:build",
    constraints: { path: %r{[a-z0-9][a-z0-9_\-./]*} }
  resources :reports, only: :show, param: :key
  resource :realtime, only: :show, controller: "realtime"
  resources :filters, only: :new
  resources :filter_options, only: :index
  resources :filter_values, only: :index
  resource :filter_dialog, only: :show
  resource :palette, only: :show
  resource :facet_search, only: :show
  resource :picker, only: :show
  resources :exports, only: :show, param: :key, defaults: { format: :csv }
  resource :view, only: :destroy
  resource :search_console, only: :show, controller: "search_console"
  resource :search_console_report, only: :show
  resource :search_console_keyword, only: :show
  resources :favicons, only: :show, param: :site, constraints: { site: %r{[^/]+} }
  resource :explore, only: :show
  resource :journey, only: :show
  namespace :visitors do
    resource :lookup, only: :show
    resources :users, only: :show, constraints: { id: %r{[^/]+} }, format: false
    resources :visits, only: :show, param: :token, constraints: { token: %r{[^/]+} }, format: false
  end
  resources :visitors, only: :index
  resources :visitors, only: :show, param: :token, constraints: { token: %r{[^/]+} }, format: false
  resource :goal_conversions, only: :show
  resource :pinned_questions, only: :show
  resources :funnels, only: [ :index, :show ]
  resource :rankings, only: :show do
    scope module: :rankings do
      resource :tags, only: [ :create, :destroy ]
    end
  end
  resource :rank_keyword, only: :show
  resource :rank_check, only: :create
  resource :ask, only: [ :show, :create, :destroy ]
  resources :chats, only: [ :index, :show, :create, :destroy ] do
    scope module: :chats do
      resources :messages, only: :create
      resources :prompts, only: :create
      resource :stream, only: :show
    end
  end

  resource :seo, only: :show, controller: "seo"

  namespace :seo do
    resource :visibility, only: :show
    resource :position_change, only: :show
    resource :landing_page, only: :show
    resource :keyword_gap, only: :show
    resource :volatility, only: :show
    resource :serp_feature, only: :show
    resource :opportunity, only: :show
    resource :cannibalization, only: :show
    resource :brand_split, only: :show
    resource :brand_terms, only: :update
    resource :conversion, only: :show

    resource :keyword_research, only: :show do
      scope module: :keyword_researches do
        resource :lookups, only: :create
        resource :refreshes, only: :create
      end
    end
    resource :backlink, only: :show do
      scope module: :backlinks do
        resource :syncs, only: :create
      end
    end
    resource :alert, only: :show do
      scope module: :alerts do
        resource :runs, only: :create
      end
    end
    resource :ai_visibility, only: :show do
      scope module: :ai_visibilities do
        resource :runs, only: :create
        resources :prompts, only: :show
      end
    end
  end

  get "settings", to: redirect { |_params, request| "#{request.script_name}/settings/goals" }

  namespace :settings do
    resources :goals, except: :show
    resources :properties, only: [ :index, :create, :update, :destroy ], param: :key,
                           constraints: { key: %r{[^/]+} }, format: false
    resources :funnels, except: :show
    resources :segments, except: :show do
      scope module: :segments do
        resource :default, only: [ :create, :destroy ]
      end
    end
    resource :default_segment, only: [ :create, :destroy ]
    namespace :exclusions do
      resource :preview, only: :show
    end
    resources :exclusions, except: :show do
      scope module: :exclusions do
        resource :state, only: :update
      end
    end
    resource :general, only: [ :edit, :update ]
    resource :default_internal_addresses, only: :create
    resource :emails, only: [ :edit, :update ]
    resources :features, only: [ :index, :update ], param: :name
    resources :saved_queries, except: :show
    resources :page_groups, except: :show
    resources :annotations, except: :show

    resource :google_authorization, only: :new
    resource :google_callback, only: :show
    resource :google_connection, only: [ :show, :destroy ]
    resource :google_credential, only: :update do
      scope module: :google_credentials do
        resources :secrets, only: :destroy, param: :key
      end
    end
    resource :search_console_property, only: [ :edit, :update ]
    resource :search_console_redirect, only: :update
    resources :search_console_rows, only: :index
    resource :search_console_sync, only: :create
    resource :search_console_backfill, only: :create
    resource :search_console_fill, only: :create

    resources :places, only: :index

    resources :serp_sites, except: :show

    resources :job_runs, only: [ :index, :show ], param: :key do
      scope module: :job_runs do
        resource :run, only: :create
      end
    end
    resources :serp_keywords, except: :show do
      scope module: :serp_keywords do
        resource :check, only: :create
      end
    end
    resource :serp_keyword_import, only: [ :new, :create ]
    resource :search_options, only: :update
    resources :serp_providers, only: [ :index, :edit, :update ], param: :name do
      scope module: :serp_providers do
        resources :secrets, only: :destroy, param: :key
      end
    end
    resources :assistant_providers, only: [ :index, :edit, :update ], param: :name do
      scope module: :assistant_providers do
        resources :secrets, only: :destroy, param: :key
        resources :models, only: :index
      end
    end
    resource :assistant_dimensions, only: [ :edit, :update ]
    resources :alert_rules, only: [ :index, :edit, :update ]
    resource :ai_visibility, only: [ :edit, :update ]
    resources :ai_visibility_assistants, only: [ :edit, :update ], param: :name do
      scope module: :ai_visibility_assistants do
        resources :secrets, only: :destroy, param: :key
      end
    end
  end

  match "*unmatched", to: "errors#show", via: :all
end
