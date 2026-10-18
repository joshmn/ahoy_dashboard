namespace :ahoy_dashboard do
  desc "report what the search console integration has and what it is missing"
  task search_console: :environment do
    feature = AhoyDashboard::FeatureState.for(:search_console)
    next puts(feature.terminal_line) unless feature.installed?

    account = AhoyDashboard::GoogleAccount.current

    puts "config"
    puts "  enabled: #{AhoyDashboard::SearchConsole.enabled?}"
    puts "  client id: #{AhoyDashboard::SearchConsole.client_id ? "stored" : "missing"}"
    puts "  client secret: #{AhoyDashboard::SearchConsole.client_secret ? "stored" : "missing"}"
    puts "  redirect uri: #{AhoyDashboard::SearchConsole.redirect_uri || "not set, the dashboard has no host"}"
    puts "  scope: #{AhoyDashboard::SearchConsole::SCOPE}"

    puts "connection"
    if account.nil?
      puts "  nothing connected"
    else
      puts "  connected: #{account.connected?}"
      puts "  property: #{account.property_uri.presence || "none picked"}"
      puts "  token expires: #{account.expires_at || "unknown"}"
      puts "  last synced: #{account.synced_at || "never"}"
      puts "  last error: #{account.last_error.presence || "none"}"
    end

    totals = AhoyDashboard::SearchConsoleTotal.count
    keywords = AhoyDashboard::SearchConsoleKeyword.count
    puts "stored"
    puts "  query x page rows: #{AhoyDashboard::SearchConsoleRow.count}"
    puts "  keyword rows: #{keywords}"
    puts "  day totals: #{totals}"
    if totals.positive?
      puts "  covering: #{AhoyDashboard::SearchConsoleTotal.minimum(:date)} to " \
           "#{AhoyDashboard::SearchConsoleTotal.maximum(:date)}"
    end
    if keywords.positive?
      puts "  keywords covering: #{AhoyDashboard::SearchConsoleKeyword.minimum(:date)} to " \
           "#{AhoyDashboard::SearchConsoleKeyword.maximum(:date)}"
    end

    if account
      floor = AhoyDashboard::SearchConsole.earliest_available_date
      reached = account.backfilled_to
      puts "backfill"
      puts "  google still serves back to: #{floor}"
      if reached.nil?
        puts "  not started, the hourly job picks it up"
      elsif reached <= floor
        puts "  finished, everything google has is here"
      else
        puts "  reached: #{reached}, #{(reached - floor).to_i} days left"
      end
    end

    routes = AhoyDashboard::Engine.routes.url_helpers
    connection_path = routes.settings_google_connection_path

    puts "next"
    if !AhoyDashboard::SearchConsole.credentials?
      puts "  set the client id and secret under settings, search console, at #{connection_path}"
    elsif !AhoyDashboard::SearchConsole.enabled?
      puts "  turn it on under settings, features"
    elsif AhoyDashboard::SearchConsole.redirect_uri.blank?
      puts "  set the host under settings, general, or the redirect url under settings, search console, " \
           "so google has somewhere to send you back"
    elsif account.nil? || !account.connected?
      puts "  publish the google cloud project, then connect at #{connection_path}"
    elsif !account.property_selected?
      puts "  pick a property at #{routes.edit_settings_search_console_property_path}"
    elsif account.last_error.present?
      puts "  reconnect google, the stored grant is not working"
    elsif totals.zero?
      puts "  run rails ahoy_dashboard:search_console_pull, or wait for the nightly job"
    else
      puts "  nothing, it is working"
    end
  end

  desc "pull search console now instead of waiting for the nightly job"
  task search_console_pull: :environment do
    feature = AhoyDashboard::FeatureState.for(:search_console)
    next puts(feature.terminal_line) unless feature.installed?

    AhoyDashboard::SearchConsole::IngestCommand.call do
      on(:ok) do |result|
        puts "pulled #{result.rows} query x page rows, #{result.keywords} keyword rows, " \
             "#{result.totals} day totals across #{result.dates.size} days"
      end
      on(:skipped) { |reason| puts "skipped: #{reason}" }
      on(:rate_limited) { |message| puts "rate limited: #{message}" }
      on(:failed) { |message| puts "failed: #{message}" }
    end
  end
end
