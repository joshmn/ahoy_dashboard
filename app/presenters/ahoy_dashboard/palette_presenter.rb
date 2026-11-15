# frozen_string_literal: true

module AhoyDashboard
  class PalettePresenter
    def initialize(query:, screen:, routes:, manage: true, assistant: true)
      @query = query
      @screen = screen
      @routes = routes
      @manage = manage
      @assistant = assistant
    end

    def path
      controls = "chart" if screen.is_a?(DashboardPresenter) || screen.is_a?(Dashboards::ShowPresenter) || screen.is_a?(Dashboards::ShellPresenter)
      @path ||= routes.palette_path(query.to_query.merge(controls: controls).compact)
    end

    def groups
      {
        "Go to" => destinations,
        "Settings" => settings,
        "Metrics" => Metric::ALL.map do |metric|
          PaletteItem.new(label: metric.label, icon: :empty, path: routes.root_path(query.with(metric: metric.key).to_query))
        end,
        "Date range" => periods,
        "SEO" => Seo::Surface::ALL.map do |surface|
          PaletteItem.new(label: surface.title, icon: :chevron_right,
            path: routes.public_send(surface.route), badge: (surface.feature_state.badge unless surface.installed?))
        end,
        "Group by" => options(:interval_options, icon: :cal),
        "Compare to" => options(:comparison_options, icon: :empty),
        "Export" => Report.cards.map do |report|
          PaletteItem.new(label: "#{report.title} as CSV", icon: :download, path: routes.export_path(report.key, query.to_query))
        end,
        "Actions" => actions
      }.reject { |_group, items| items.empty? }
    end

    private

    attr_reader :query, :screen, :routes, :manage, :assistant

    def settings
      return [] unless manage

      SettingsSection::ALL.map do |section|
        PaletteItem.new(label: section.label, icon: :gear, path: routes.public_send(section.route), badge: section.badge)
      end
    end

    def destinations
      [
        PaletteItem.new(label: "Dashboard", icon: :home, path: routes.root_path),
        PaletteItem.new(label: "Realtime", icon: :monitor, path: routes.realtime_path),
        PaletteItem.new(label: "Explore", icon: :compass, path: routes.explore_path),
        PaletteItem.new(label: "Visitors", icon: :user, path: routes.visitors_path(query.to_query)),
        PaletteItem.new(label: "SEO", icon: :search, path: routes.seo_path,
          badge: (FeatureState::BADGE unless Seo::Surface.installed?(Seo::Surface::FEATURES))),
        (PaletteItem.new(label: "Ask", icon: :chat, path: routes.chats_path,
          badge: (FeatureState::BADGE unless Installation.installed?(:assistant))) if assistant)
      ].compact
    end

    def periods
      options = PeriodMenu.items(query: query, custom: false) do |period|
        routes.root_path(query.to_query.merge(period: period.key).except(:from, :to))
      end

      options.map { |option| PaletteItem.new(label: option.label, icon: :cal, path: option.path) }
    end

    def options(name, icon:)
      return [] unless screen.respond_to?(name)

      screen.public_send(name).map do |option|
        PaletteItem.new(label: option.label, icon: icon, path: option.path)
      end
    end

    def actions
      comparing = query.comparison.present?
      items = [
        PaletteItem.new(label: comparing ? "Stop comparing" : "Compare to the previous period", icon: :empty,
          path: routes.root_path(query.with(comparison: comparing ? nil : "previous_period").to_query)),
        PaletteItem.new(label: query.include_crawlers? ? "Hide crawlers" : "Show crawlers", icon: :filter,
          path: routes.root_path(query.crawler_toggle_params))
      ]

      if Sql::ExcludedTraffic.enabled?
        items << PaletteItem.new(label: query.include_internal? ? "Hide hidden traffic" : "Show hidden traffic", icon: :filter,
          path: routes.root_path(query.internal_toggle_params))
      end

      if query.filters.any?
        items.unshift(PaletteItem.new(label: "Clear all filters", icon: :close,
          path: routes.root_path(query.with(filters: nil).to_query)))
      end

      items
    end
  end
end
