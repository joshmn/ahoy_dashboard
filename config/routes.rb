AhoyDashboard::Engine.routes.draw do
  root "dashboards#show"
  resource :dashboard, only: :show, controller: "dashboards" do
    scope module: :dashboards do
      resource :summary, only: :show
    end
  end
  resource :styleguide, only: :show, controller: "styleguides" if Rails.env.development? || Rails.env.test?
  # The dashboard's own stylesheet and its ES module tree. Served by us rather
  # than by the host's asset pipeline, so nothing here needs propshaft, an
  # importmap or a bundler. The build digest is a path segment because the
  # modules import each other relatively.
  resources :assets, only: :show, param: :path, path: "assets/:build",
    constraints: { path: %r{[a-z0-9][a-z0-9_\-./]*} }
  # One report card. The key is which breakdown, the tab is which dimension
  # inside it, so a card and its details modal are the same resource.
  resources :reports, only: :show, param: :key
  resource :realtime, only: :show, controller: "realtime"
  # The add-a-filter form for one category of dimensions. A page rather than
  # markup on the dashboard, so the dialog is a frame over something that
  # still works with the JavaScript off. Applying it is a GET to the dashboard,
  # which is why there is no create.
  resources :filters, only: :new
  # Values a filter can take, for the filter dropdown's typeahead.
  resources :filter_options, only: :index
  # The filter popover itself: no dimension is the list of dimensions, a
  # dimension is its values. One resource, because it is one panel swapping
  # what is inside it, and the back button is this index without the param.
  resources :filter_values, only: :index
  resource :filter_dialog, only: :show
  resource :palette, only: :show
  # One search across every dimension at once, for when somebody knows the
  # value and not which dimension holds it. Singular, because the search is
  # the query string rather than a record.
  resource :facet_search, only: :show, controller: "facet_searches"
  # The value picker behind the settings forms: facets, then one facet's
  # options. Its own resource rather than a mode of the popover above, because
  # picking here writes into a form field instead of navigating, so every row
  # is a button rather than a link.
  resource :picker, only: :show, controller: "pickers"
  resources :exports, only: :show, param: :key, defaults: { format: :csv }
  # The remembered view lives in a cookie, so forgetting it is a destroy.
  resource :view, only: :destroy, controller: "views"
  # Not a report card. Search Console is a different table at a different grain
  # with no visitor in it, so it cannot answer a filter and has no dimension.
  resource :search_console, only: :show, controller: "search_console"
  # The whole of what has been pulled from Google, at every grain it was pulled
  # at. The card above answers what search did for the range; this answers what
  # is actually stored and says which table each block came from.
  resource :search_console_report, only: :show, controller: "search_console_reports"
  # One keyword's own history. Singular and keyed by the query string, because
  # a search term is arbitrary text and a slash or a dot in one is not a route.
  resource :search_console_keyword, only: :show, controller: "search_console_keywords"
  # Icons are fetched and cached by us, so the admin's browser never tells a
  # third party which sites send this one traffic.
  # param: :site rather than :domain, because :domain is one of url_for's own
  # reserved options for host building, so it gets stripped before the path is
  # generated and favicon_path("x.com") raises missing required keys.
  # :host is reserved for the same reason. Do not rename this back.
  resources :favicons, only: :show, param: :site, constraints: { site: %r{[^/]+} }
  # One composed question rather than the grid of pre-decided ones. Singular,
  # because the question is the query string: which dimension, which columns,
  # which page of them, on top of everything QueryForm already carries. The CSV
  # is the same resource in another representation rather than an export key,
  # because there is no report key to name.
  resource :explore, only: :show, controller: "explores"
  # What people did next. Its own resource because it reads sequences rather
  # than a breakdown, so it answers none of the report machinery's questions.
  resource :journey, only: :show, controller: "journeys"
  # Goals, full width under the journey. Its own resource rather than a report
  # card: a report is a card with tabs in a half-width column, and this is a
  # section with three numbers per row.
  resource :goal_conversions, only: :show, controller: "goal_conversions"
  # The pinned saved questions, as cards under the chart. Its own resource and
  # its own frame because each card is a pair of queries over a range of its
  # own, and none of that should hold up the rest of the dashboard.
  resource :pinned_questions, only: :show, controller: "pinned_questions"
  resources :funnels, only: [ :index, :show ], param: :id
  # Where the site actually comes on the results page. Its own surface rather
  # than a report card, the same reason search console is: a serp row carries
  # no visitor, so it can answer no filter and narrow nothing.
  resource :rankings, only: :show, controller: "rankings" do
    scope module: :rankings do
      resource :tags, only: [ :create, :destroy ]
    end
  end
  # One tracked keyword over time. Singular and keyed by the query string, for
  # the same reason the search console one is.
  resource :rank_keyword, only: :show, controller: "rank_keywords"
  # Running the whole of the tracking now instead of waiting for each search's
  # cadence. Its own resource because launching a sweep is not editing a
  # keyword, and the button that does it belongs beside the readings rather
  # than in settings.
  resource :rank_check, only: :create, controller: "rank_checks"
  # Asking the data a question in words. A chat is a record because the answer
  # is worked out in a job and the page waits for it, so there is somewhere for
  # a half finished turn to live.
  # The same assistant, opened over whatever screen somebody is already on. Its
  # own resource rather than an action on chats because what it creates is not
  # a conversation, it is a question about a page: the screen, the window and
  # the filters that were on it get snapshotted onto the chat, and that is the
  # whole difference between this and the Ask screen.
  resource :ask, only: [ :show, :create, :destroy ], controller: "asks"
  resources :chats, only: [ :index, :show, :create, :destroy ] do
    scope module: :chats do
      resources :messages, only: :create
      # The answer as it is written. Its own resource because it is a live
      # response rather than a page: the job writes the half finished answer
      # to the row and this reads that row out to the browser until it stops
      # changing.
      resource :stream, only: :show, controller: "streams"
    end
  end

  # The SEO suite. One hub and fourteen surfaces under it, plus the two that
  # already existed and are listed alongside them, because each answers
  # a different question and none of them is a report card: a serp row and a
  # search console row carry no visitor, so they narrow under no filter and
  # belong nowhere near the dashboard's report machinery.
  #
  # Nine read what is already stored. Five are drawn against sample data and say
  # so on the page, because the tables they want do not exist yet.
  resource :seo, only: :show, controller: "seo"

  namespace :seo do
    # Reads what is already stored.
    resource :visibility, only: :show
    resource :position_change, only: :show
    resource :landing_page, only: :show
    resource :keyword_gap, only: :show
    resource :volatility, only: :show
    resource :serp_feature, only: :show
    resource :opportunity, only: :show
    resource :cannibalization, only: :show
    resource :brand_split, only: :show
    resource :brand_terms, only: :update, controller: "brand_terms"
    resource :conversion, only: :show

    resource :keyword_research, only: :show do
      scope module: :keyword_researches do
        # Spending money is not reading the cache, so it is its own resource and
        # a POST. Opening the report must never cost anything.
        resource :lookups, only: :create, controller: "lookups"
        resource :refreshes, only: :create, controller: "refreshes"
      end
    end
    resource :backlink, only: :show do
      scope module: :backlinks do
        resource :syncs, only: :create, controller: "syncs"
      end
    end
    resource :alert, only: :show do
      scope module: :alerts do
        resource :runs, only: :create, controller: "runs"
      end
    end
    resource :ai_visibility, only: :show, controller: "ai_visibilities" do
      scope module: :ai_visibilities do
        resource :runs, only: :create, controller: "runs"
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
    # A question saved out of Explore. Its params are the whole record, so
    # opening one is a navigation rather than a rebuild.
    resources :saved_queries, except: :show
    # Which noisy paths fold into one name on the Pages card. Nothing is
    # rewritten on the way in, so a rule written today folds the whole history
    # and switching it off shows the paths back.
    resources :page_groups, except: :show
    # What happened on a day, marked on the chart.
    resources :annotations, except: :show

    # The Google dance is one resource per verb rather than one controller
    # with four actions. new redirects to Google; the callback has to be a
    # show because Google's redirect is a GET, and the state param is what
    # stands in for CSRF there.
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
    # Every stored row as it landed. Its own resource because it answers a
    # different question from the card: not what is going on, but what actually
    # came through.
    resources :search_console_rows, only: :index
    resource :search_console_sync, only: :create
    # Reaching backwards rather than re-reading the fresh window. Its own
    # resource for the reason the job has its own schedule: the two never run
    # for the same reason and one must never hold up the other.
    resource :search_console_backfill, only: :create
    # Going back for days inside the record that never landed. A third resource
    # rather than a mode of either one above it: the sync keeps the top current,
    # the backfill extends the bottom, and this one fills what both walked past.
    resource :search_console_fill, only: :create

    # Somewhere to search from, one step of the tree at a time. Read only and a
    # frame: it fills in a field on the keyword forms and never navigates, so
    # there is nothing here but an index.
    resources :places, only: :index

    # Rank tracking. Sites and keywords are separate resources because one
    # search is shared by every site attached to it, which is the whole reason
    # attaching another one costs nothing.
    resources :serp_sites, except: :show

    # What the schedule is doing, and starting one entry now. The run is its own
    # resource because starting a job is not editing the row that records it.
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
    # Many at once, off the back of what Search Console already knows people
    # searched. Its own resource because importing is not creating a keyword,
    # it is creating a hundred of them under one set of settings.
    resource :serp_keyword_import, only: [ :new, :create ]
    resource :search_options, only: :update
    resources :serp_providers, only: [ :index, :edit, :update ], param: :name do
      scope module: :serp_providers do
        resources :secrets, only: :destroy, param: :key
      end
    end
    # Which model answers, and its key. One row per reader so a key for each
    # can sit there and switching is flipping which one is active.
    resources :assistant_providers, only: [ :index, :edit, :update ], param: :name do
      scope module: :assistant_providers do
        resources :secrets, only: :destroy, param: :key
      end
    end
    resource :assistant_dimensions, only: [ :edit, :update ]
    # Which alert rules are on and what each one's number is. Only those two:
    # the question a rule asks is code, and a screen that let somebody rewrite
    # it would be a rules engine nobody asked for.
    resources :alert_rules, only: [ :index, :edit, :update ]
    resource :ai_visibility, only: [ :edit, :update ], controller: "ai_visibilities"
    resources :ai_visibility_assistants, only: [ :edit, :update ], param: :name do
      scope module: :ai_visibility_assistants do
        resources :secrets, only: :destroy, param: :key
      end
    end
  end

  match "*unmatched", to: "errors#show", via: :all
end
