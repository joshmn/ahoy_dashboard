namespace :ahoy_dashboard do
  desc "report what the serp tracking layer is configured with"
  task serp: :environment do
    feature = AhoyDashboard::FeatureState.for(:serp)
    next puts(feature.terminal_line) unless feature.installed?

    puts "config"
    puts "  enabled: #{AhoyDashboard::Serp.enabled?}"
    puts "  provider: #{AhoyDashboard::Serp.provider}"
    puts "  own domain: #{AhoyDashboard::Serp.own_domain || "not set"}"

    puts "adapters"
    AhoyDashboard::Serp.adapter_names.each do |name|
      adapter = AhoyDashboard::Serp.adapter_class(name)
      state = adapter.configured? ? "configured" : "no credentials"
      active = name == AhoyDashboard::Serp.provider ? ", active" : ""

      puts "  #{name}: #{state}#{active}"
    end

    puts "stored"
    puts "  sites: #{AhoyDashboard::SerpSite.count}"
    puts "  keywords: #{AhoyDashboard::SerpKeyword.count}, #{AhoyDashboard::SerpKeyword.where(enabled: true).count} being checked"
    puts "  searches run: #{AhoyDashboard::SerpRun.count}"
    puts "  positions recorded: #{AhoyDashboard::SerpCheck.count}"
    puts "  ai citations: #{AhoyDashboard::SerpAiCitation.count}"

    due = AhoyDashboard::SerpKeyword.due.count
    puts "  due right now: #{due}"

    spend = AhoyDashboard::Serp::SpendQuery.call
    record = AhoyDashboard::SerpProvider.current

    puts "spend"
    puts "  ceiling: #{spend.capped? ? spend.cap : "none"}"
    puts "  used this month: #{spend.used}#{spend.capped? ? " (#{spend.percent}%)" : ""}"
    AhoyDashboard::SerpSpendDay::KINDS.each_key do |kind|
      puts "  #{kind}: #{spend.count(kind)}"
    end
    puts "  scheduled to #{spend.forecast.through.to_date}: #{spend.forecast.total}"
    puts "  ending the month at: #{spend.projected}#{spend.over? ? ", stopped at #{spend.cap} by the ceiling" : ""}"
    puts "  last error: #{record.last_error.presence || "none"}" if record

    puts "next"
    if AhoyDashboard::Serp.provider == :fake
      puts "  pick a real provider under settings, search provider, and save its key"
    elsif !AhoyDashboard::Serp.configured?
      puts "  #{AhoyDashboard::Serp.provider} is selected but has no credentials"
    else
      puts "  ready, try ahoy_dashboard:serp_search"
    end
  end

  desc "write the ranking rows for stored searches that predate them"
  task serp_backfill_results: :environment do
    feature = AhoyDashboard::FeatureState.for(:serp)
    next puts(feature.terminal_line) unless feature.installed?

    written = 0
    missing = 0

    AhoyDashboard::SerpRun.usable.left_joins(:results).where(ahoy_dashboard_serp_results: { id: nil }).includes(:run_pages).find_each do |run|
      AhoyDashboard::Serp::Results::StoreCommand.call(run: run) do
        on(:ok) { |rows| written += rows.size }
        on(:nothing) { missing += 1 }
      end
    end

    puts "wrote #{written} ranking rows"
    puts "#{missing} searches had no readable page stored" if missing.positive?
  end

  desc "check one tracked keyword now instead of waiting for the dispatcher"
  task :serp_check, [ :query, :location ] => :environment do |_task, args|
    feature = AhoyDashboard::FeatureState.for(:serp)
    next puts(feature.terminal_line) unless feature.installed?

    keyword = AhoyDashboard::Serp::KeywordLookupQuery.call(text: args[:query], location: args[:location])
    abort "no keyword called #{args[:query].inspect}" if keyword.nil?

    location = args[:location].presence || keyword.locations.first

    AhoyDashboard::Serp::Checks::RunCommand.call(keyword: keyword, location: location) do
      on(:ok) do |outcome|
        puts "checked #{keyword.query} at #{location}, #{outcome.units} units"
        outcome.checks.each do |check|
          where = check.position ? "position #{check.position}" : "nowhere in these results"
          puts "  #{check.site.domain}: #{where}"
        end
        puts "  ai overview cited #{outcome.citations.size} sources" if outcome.citations.any?
      end
      on(:skipped) { |reason| puts "skipped: #{reason}" }
      on(:capped) { puts "skipped, the monthly ceiling is reached" }
      on(:rate_limited) { |message| puts "quota: #{message}" }
      on(:failed) { |message| puts "failed: #{message}" }
    end
  end

  desc "run one search through the active adapter and print what came back"
  task :serp_search, [ :query, :location, :pages ] => :environment do |_task, args|
    query = args[:query].presence
    abort "give it a query: rails 'ahoy_dashboard:serp_search[federal prison visiting hours]'" if query.blank?
    feature = AhoyDashboard::FeatureState.for(:serp)
    next puts(feature.terminal_line) unless feature.installed?

    abort "serp tracking is switched off. switch it on under settings, features" unless AhoyDashboard::Serp.enabled?

    location = AhoyDashboard::Serp::Location.parse(args[:location])
    pages = (args[:pages].presence || 1).to_i
    record = AhoyDashboard::SerpProvider.current
    adapter_class = record&.adapter_class || AhoyDashboard::Serp.adapter_class
    abort "#{adapter_class.adapter_name} has no credentials" unless adapter_class.configured?

    adapter = adapter_class.new
    units = adapter_class.cost_units(pages: pages)

    puts "searching"
    puts "  provider: #{adapter.provider_name}"
    puts "  query: #{query}"
    puts "  location: #{location} (#{location.label})"
    puts "  pages: #{pages}, costing #{units} units"

    spend = AhoyDashboard::Serp::Spend.new(provider: record, units: units, kind: :checks,
                                           name: adapter_class.adapter_name)
    abort "skipped, the monthly ceiling is reached so nothing was sent" unless spend.reserve

    spent = 0
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      results = adapter_class.requests_for(pages: pages).map do |request|
        adapter.search(query: query, request: request, location: location).tap { |page| spent += page.cost_units.to_i }
      end
      spend.settle(spent, used: true)
    rescue AhoyDashboard::Serp::Error => e
      spend.settle(spent)
      record&.record_error!(e.message)
      abort "failed: #{e.message}"
    ensure
      spend.settle(spent)
    end
    result = AhoyDashboard::Serp::Result.combine(results)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    puts "results in #{elapsed}ms"
    result.organic.each do |entry|
      puts "  #{entry.position.to_s.rjust(3)}. #{entry.domain} #{entry.link}"
    end

    own = AhoyDashboard::Serp.own_domain
    if own.present?
      rank = result.rank_for(own)
      puts "us"
      puts "  #{own}: #{rank ? "position #{rank.position}, #{rank.link}" : "not in these results"}"
    end

    puts "ai overview"
    if result.ai_overview.shown?
      puts "  shown, #{result.ai_overview.sources.size} sources#{result.ai_overview.deferred? ? ", deferred" : ""}"
      result.ai_overview.sources.each { |source| puts "  #{source.index}. #{source.domain} #{source.link}" }
      puts "  cites us: #{own.present? ? result.cited?(own) : "no own domain set"}"
    else
      puts "  none"
    end
  end
end
