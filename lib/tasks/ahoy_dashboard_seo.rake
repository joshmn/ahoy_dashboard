namespace :ahoy_dashboard do
  desc "fetch keyword ideas for a seed phrase"
  task :keywords, [ :seed, :refresh ] => :environment do |_task, args|
    feature = AhoyDashboard::FeatureState.for(:keywords)
    next puts(feature.terminal_line) unless feature.installed?

    abort "give it a seed: rails ahoy_dashboard:keywords[federal prison]" if args[:seed].blank?

    refresh = args[:refresh].to_s == "refresh"

    AhoyDashboard::Keywords::FetchCommand.call(seed: args[:seed], refresh: refresh) do
      on(:ok) { |outcome| puts "stored #{outcome.written} ideas for #{outcome.seed}, #{outcome.units} units" }
      on(:saved) { puts "#{args[:seed]} is already saved, nothing bought. add refresh to buy it again: rails 'ahoy_dashboard:keywords[#{args[:seed]},refresh]'" }
      on(:capped) { abort "skipped, the monthly ceiling is reached" }
      on(:refused) { |message| abort message.downcase }
      on(:disabled) { abort "keyword data is switched off. switch it on under settings, features" }
      on(:unsupported) { |provider| abort "#{provider} does not sell keyword data" }
      on(:rate_limited) { |message| abort "quota: #{message}" }
      on(:failed) { |message| abort "failed: #{message}" }
      on(:invalid) { |message| abort message }
    end
  end

  desc "pull the backlink profile and reconcile it"
  task backlinks: :environment do
    feature = AhoyDashboard::FeatureState.for(:backlinks)
    next puts(feature.terminal_line) unless feature.installed?

    AhoyDashboard::Backlinks::SyncCommand.call do
      on(:ok) { |outcome| puts "#{outcome.domains} domains, #{outcome.gained} new, #{outcome.lost} gone, #{outcome.returned} back" }
      on(:disabled) { abort "backlink data is switched off. switch it on under settings, features" }
      on(:capped) { abort "skipped, the monthly ceiling is reached" }
      on(:refused) { |message| abort message.downcase }
      on(:unsupported) { |provider| abort "#{provider} does not sell backlink data" }
      on(:rate_limited) { |message| abort "quota: #{message}" }
      on(:failed) { |message| abort "failed: #{message}" }
      on(:invalid) { |message| abort message }
    end
  end

  desc "evaluate every alert rule that is switched on"
  task alerts: :environment do
    feature = AhoyDashboard::FeatureState.for(:alerts)
    next puts(feature.terminal_line) unless feature.installed?

    AhoyDashboard::Alerts::Rules::InstallCommand.call

    AhoyDashboard::Alerts::RunCommand.call do
      on(:ok) do |outcome|
        puts "fired #{outcome.fired.size}, delivered #{outcome.delivered}, #{outcome.repeats} already said"
        outcome.fired.each { |event| puts "  #{event.severity.ljust(6)} #{event.headline}" }
      end
      on(:disabled) { abort "alerts are switched off. switch them on under settings, features" }
      on(:nothing_on) { puts "no rule is switched on" }
    end
  end

  desc "install the alert rules, all switched off"
  task alert_rules: :environment do
    feature = AhoyDashboard::FeatureState.for(:alerts)
    next puts(feature.terminal_line) unless feature.installed?

    AhoyDashboard::Alerts::Rules::InstallCommand.call

    AhoyDashboard::AlertRule.ordered.each do |rule|
      waiting = rule.waiting_on
      note = if waiting.nil?
        ""
      elsif waiting.names.one?
        ", cannot run until #{waiting.label.downcase} is installed. #{AhoyDashboard::Schedule.install_steps(waiting.names)}"
      else
        ", cannot run until one of #{waiting.label.downcase} is installed. run bin/rails generate " \
          "ahoy_dashboard:install --only one of #{waiting.names.join(", ")}, then bin/rails db:migrate"
      end

      puts "#{rule.enabled ? "on " : "off"}  #{rule.key.ljust(20)}  #{rule.condition}#{note}"
    end
  end
end
