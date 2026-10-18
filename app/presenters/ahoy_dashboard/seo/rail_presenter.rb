module AhoyDashboard
  module Seo
    class RailPresenter
      OVERVIEW = "seo".freeze
      MENU_LABEL = "SEO".freeze

      Item = Data.define(:key, :label, :url, :current, :ready, :state) do
        def current?
          current
        end

        def ready?
          ready
        end

        def installed?
          state.nil?
        end
      end

      attr_reader :query, :current, :site, :tag

      def initialize(query:, current:, site: nil, tag: nil, available: [])
        @query = query
        @current = current.to_s
        @site = site
        @tag = tag.presence
        @available = available
      end

      def overview
        Item.new(key: OVERVIEW, label: "Overview", url: routes.seo_path(carried),
                 current: current == OVERVIEW, ready: true, state: nil)
      end

      def groups
        @groups ||= Surface.grouped.map do |group, surfaces|
          [ group, surfaces.map { |surface| item_for(surface) } ]
        end
      end

      def current_label
        [ overview, *groups.flat_map(&:last) ].find(&:current?)&.label || MENU_LABEL
      end

      def menu_groups
        [ [ MENU_LABEL, [ overview ] ], *groups ].map do |group, items|
          [ group, items.map { |item| menu_item(item) } ]
        end
      end

      private

      def menu_item(item)
        { label: item.label, url: item.url, active: item.current?, note: menu_note(item),
          data: AhoyDashboard::SetupNotice::TOP }
      end

      def menu_note(item)
        return item.state.badge unless item.installed?

        "No data yet" unless item.ready?
      end

      def item_for(surface)
        installed = surface.installed?

        Item.new(key: surface.key, label: surface.title, url: surface.path(carried),
                 current: surface.key == current, ready: installed && ready?(surface),
                 state: (surface.feature_state unless installed))
      end

      attr_reader :available

      def ready?(surface)
        Array(surface.needs).all? { |need| Array(need).any? { |one| available.include?(one) } }
      end

      def carried
        query.to_query.merge({ site: site&.id, tag: tag }.compact)
      end

      def routes
        AhoyDashboard::Engine.routes.url_helpers
      end
    end
  end
end
