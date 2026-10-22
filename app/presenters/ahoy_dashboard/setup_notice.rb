module AhoyDashboard
  module SetupNotice
    TOP = { tm_frame: "_top" }.freeze

    STEPS = {
      google: {
        title: "Connect Google Search Console to get started",
        hint: "Clicks, impressions and positions from Google show here once it is connected.",
        label: "Connect Search Console"
      },
      property: {
        title: "Pick a Search Console property to get started",
        hint: "Google is connected, but nothing syncs until you pick which site to read.",
        label: "Pick a property"
      },
      site: {
        title: "Add your site to get started",
        hint: "Rank checks look for your domain in the results, so they need to know which one is yours.",
        label: "Add your site"
      },
      keywords: {
        title: "Add your keywords to get started",
        hint: "Pick the searches you want to rank for, and every check records where your site shows up.",
        label: "Track keywords"
      },
      competitor: {
        title: "Add a competitor to get started",
        hint: "Add a competitor's domain and attach it to searches you already track. " \
              "Their positions come from the same checks, so it costs nothing extra.",
        label: "Add a competitor"
      },
      goal: {
        title: "Add a goal to get started",
        hint: "Conversions show here once a goal says which page visit or event counts. It counts past visits too.",
        label: "New goal"
      },
      alerts: {
        title: "Turn on alerts to get started",
        hint: "Alerts are off. Switch them on under Settings, Features, then turn on the rules you want.",
        label: "Switch on alerts"
      },
      alert_rule: {
        title: "Turn on a rule to get started",
        hint: "Alerts only fire for rules that are on. Pick the ones you want to watch.",
        label: "Alert rules"
      },
      alert_emails: {
        title: "Set up alert emails to hear about alerts",
        label: "Set up alert emails"
      },
      ai_visibility: {
        title: "Turn on AI visibility to get started",
        hint: "AI visibility is off. Every answer is a paid request, so it stays off until you " \
              "switch it on under Settings, Features."
      },
      ai_assistant: {
        title: "Turn on an assistant to get started",
        hint: "Every assistant that is on and has a key is asked your prompts.",
        label: "Set up an assistant"
      },
      ai_prompts: {
        title: "Write your prompts to get started",
        hint: "Write the questions you want to show up in, one per line.",
        label: "Write prompts"
      },
      keyword_research: {
        title: "Turn on keyword research to get started",
        hint: "Keyword research is off. It uses a paid keyword data provider, so it stays off until you " \
              "switch it on under Settings, Features."
      },
      keyword_provider: {
        title: "Choose a provider with keyword data to get started",
        hint: "Your search provider does not sell keyword data. Pick one that does to look up new ideas.",
        label: "Choose a search provider"
      },
      backlinks: {
        title: "Turn on backlinks to get started",
        hint: "Backlinks are off. They come from a paid provider, so they stay off until you " \
              "switch them on under Settings, Features."
      },
      backlink_provider: {
        title: "Choose a provider with backlink data to get started",
        hint: "Your search provider does not sell backlink data. Pick one that does to sync the sites that link to you.",
        label: "Choose a search provider"
      },
      provider_credentials: {
        title: "Add your search provider's credentials to get started",
        hint: "Your search provider has no credentials set, so nothing can be looked up yet.",
        label: "Add credentials"
      },
      backlink_host: {
        title: "Set your site's host to get started",
        hint: AhoyDashboard::Backlinks::NO_HOST_MESSAGE,
        label: "Set the host"
      },
      backlink_sample: {
        title: "Choose a real search provider to get started",
        hint: "Backlinks are never synced from sample data, because made up sites would land in your real history.",
        label: "Choose a search provider"
      }
    }.freeze

    def self.call(step, url: nil, hint: nil)
      entry = STEPS.fetch(step)
      action = { label: entry[:label], url: url, data: TOP, permission: :manage } if url && entry[:label]

      { title: entry[:title], hint: hint || entry[:hint], action: action }.compact
    end

    def self.google_account
      (AhoyDashboard::GoogleAccount.current if AhoyDashboard::SearchConsole.installed?)
    end

    def self.search_console_step(account = google_account)
      account&.connected? ? :property : :google
    end

    def self.search_console(routes, account: google_account, hint: nil)
      step = search_console_step(account)

      call(step, url: search_console_url(routes, step), hint: hint)
    end

    def self.search_console_url(routes, step)
      step == :property ? routes.edit_settings_search_console_property_path : routes.settings_google_connection_path
    end
  end
end
