module AhoyDashboard
  module Seo
    class BasePresenter
      include AhoyDashboard::Seo::Exportable
      include AhoyDashboard::Seo::Formatting

      Tile = Data.define(:label, :value, :note, :tone, :kind, :url) do
        def initialize(label:, value:, note: nil, tone: nil, kind: :number, url: nil)
          super
        end
      end

      Group = Data.define(:key, :title, :note, :rows, :tone)

      BOUGHT = %w[serp_ keyword_ideas backlink_].freeze

      TOP = AhoyDashboard::SetupNotice::TOP

      SLICEABLE = %w[opportunities cannibalization brand_split conversions].freeze

      SHARE_FLOOR = 3

      attr_reader :query, :surface, :site, :sites, :result, :slice, :tag, :tags, :totals

      def initialize(query:, surface:, result: nil, site: nil, sites: [], slice: nil, tag: nil, tags: [],
        totals: nil, search_console_context: SearchConsole::PageContext.new)
        @query = query
        @surface = surface
        @result = result
        @site = site
        @sites = sites
        @tag = tag.presence
        @tags = tags
        @slice = sliceable? && slice ? slice : AhoyDashboard::SearchConsole::Slice.new
        @totals = totals
        @search_console_context = search_console_context
      end

      def sliceable?
        SLICEABLE.include?(surface&.key)
      end

      def slice_menus
        memo(:slice_menus) do
          AhoyDashboard::SearchConsoleSlicePresenter.new(
            slice: slice, countries: search_console_context.countries,
            path: ->(chosen) { surface.path(query.to_query.merge(site_param).merge(chosen).compact) }
          )
        end
      end

      def title
        rival? ? "#{surface.title}: #{site.name}" : surface.title
      end

      def blurb
        return surface.blurb unless rival?

        surface.blurb.sub("your site", site.name).sub("your tracked searches", "your tracked searches, read for #{site.name}")
      end

      def rival?
        site.present? && !site.ours?
      end

      def mine?(domain)
        AhoyDashboard::Serp::Domain.matches_site?(domain, site)
      end

      def site_label
        "Site: #{site&.name || "none"}"
      end

      def bought?
        BOUGHT.any? { |table| surface&.reads.to_s.include?(table) }
      end

      def invented?
        bought? && Serp.provider.to_sym == :fake
      end

      def search_console?
        surface&.reads.to_s.include?("search_console")
      end

      def providers_path
        routes.settings_serp_providers_path
      end

      def search_path(text)
        routes.search_console_keyword_path(query.to_query.merge(slice_param).merge(q: text))
      end

      def tracked_path(row)
        place = row.respond_to?(:place) ? row.place.to_s : (row.location if row.respond_to?(:location))

        record = row.keyword if row.respond_to?(:keyword) && row.keyword.respond_to?(:id)
        lookup = record ? { keyword: record.id } : { q: row.query }

        routes.rank_keyword_path(query.to_query.merge(lookup).merge(at: place.presence, site: site&.id).compact)
      end

      def export_key
        surface.export
      end

      def export_path(params)
        surface.path(params)
      end

      def export_params
        query.to_query.merge(link_param).merge(carried)
      end

      def carried
        {}
      end

      def tiles
        []
      end

      def any?
        result.respond_to?(:any?) ? result.any? : result.present?
      end

      def period_options
        Periods.menu(query) { |period| surface.path(query.with(period: period.key).to_query.merge(link_param)) }
      end

      def site_options
        sites.map do |candidate|
          {
            label: "#{candidate.name} (#{candidate.domain})",
            url: surface.path(query.to_query.merge(link_param).merge(site: candidate.id)),
            active: candidate.id == site&.id
          }
        end
      end

      def range_label
        query.range_title
      end

      def show_sites?
        sites.many?
      end

      def show_tags?
        surface&.group == "Rank tracking" && tag_menu.show?
      end

      def tag_menu
        memo(:tag_menu) do
          Serp::TagMenu.new(tags: tags, current: tag,
                            url: ->(chosen) { surface.path(query.to_query.merge(link_param).merge(tag: chosen).compact) })
        end
      end

      def rankings_path
        routes.rankings_path(query.to_query.merge(tag_param))
      end

      def keywords_path
        routes.settings_serp_keywords_path
      end

      def new_keyword_path
        routes.new_settings_serp_keyword_path
      end

      def new_site_path
        routes.new_settings_serp_site_path
      end

      def search_console_path
        routes.settings_google_connection_path
      end

      def new_goal_path
        routes.new_settings_goal_path
      end

      def alert_rules_path
        routes.settings_alert_rules_path
      end

      def connected?
        search_console_context.connected?
      end

      def tracking?
        memo(:tracking) { AhoyDashboard::Serp.installed? && AhoyDashboard::SerpKeyword.exists? }
      end

      def site?
        sites.any?
      end

      def search_console_empty(title: "No Search Console data in this range",
                               hint: "Google reports two to three days late. Try a longer date range.")
        return { title: title, hint: slice.empty_hint, action: slice_menus.clear_action(data: TOP) } if slice.any?

        SearchConsoleEmptyState.call(query: query, context: search_console_context, routes: routes, title: title, hint: hint,
                                     path: ->(overrides) { surface.path(query.with(overrides).to_query.merge(link_param)) })
      end

      def data_note
        AhoyDashboard::SearchConsoleReportPresenter.data_note(
          through: on_label(totals.last_date), slice: slice,
          sliced: "Days pulled before the dashboard stored device and country are left out. " \
                  "#{AhoyDashboard::SearchConsoleReportPresenter::ROWS_NOTE}"
        )
      end

      def narrow?
        !Periods.wide_enough?(query)
      end

      def widen_action
        { label: Periods.widen_label, data: TOP, primary: true,
          url: surface.path(Periods.widened(query).merge(link_param)) }
      end

      def rank_empty(title: "No readings in this range", hint: "Try a longer date range.")
        return AhoyDashboard::SetupNotice.call(:site, url: new_site_path) unless site?
        return AhoyDashboard::SetupNotice.call(:keywords, url: new_keyword_path) unless tracking?

        return { title: title, hint: hint, action: widen_action } if narrow?

        if tag
          return { title: title, hint: "No tracked search tagged #{tag} was read in this range.",
                   action: tag_menu.clear_action(data: TOP) }
        end

        { title: title, hint: hint, action: { label: "Open Rankings", url: rankings_path, data: TOP, primary: false } }
      end

      private

      attr_reader :search_console_context

      def site_param
        site ? { site: site.id } : {}
      end

      def slice_param
        slice.to_query
      end

      def tag_param
        tag ? { tag: tag } : {}
      end

      def link_param
        site_param.merge(slice_param).merge(tag_param)
      end

      def movement(change)
        return :none if change.nil?
        return :level if change.zero?

        change.positive? ? :up : :down
      end

      def csv_change(row)
        case change_kind(row)
        when :new then "New"
        when :gone then "Gone"
        else row.change
        end
      end

      def memo(name)
        @memo ||= {}
        return @memo[name] if @memo.key?(name)

        @memo[name] = yield
      end

      def routes
        AhoyDashboard::Engine.routes.url_helpers
      end
    end
  end
end
