module AhoyDashboard
  module Seo
    # What every surface in the suite needs and none of them should write twice:
    # the range control, the site control, the empty states that point at the
    # setup page, and the handful of formatters that keep a percentage looking
    # the same on all of them.
    class BasePresenter
      include AhoyDashboard::Seo::Exportable

      Tile = Data.define(:label, :value, :note, :tone, :kind, :url) do
        def initialize(label:, value:, note: nil, tone: nil, kind: :number, url: nil)
          super
        end
      end

      DASH = "&mdash;".html_safe

      BOUGHT = %w[serp_ keyword_ideas backlink_].freeze

      TOP = { tm_frame: "_top" }.freeze

      SLICEABLE = %w[opportunities cannibalization brand_split conversions].freeze

      attr_reader :query, :surface, :site, :sites, :result, :slice, :tag, :totals

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

      def site_label
        "Site: #{site&.name || "none"}"
      end

      def sample?
        surface.sample?
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
        AhoyDashboard::SeoRange.periods.map do |period|
          {
            label: period.label,
            url: surface.path(query.with(period: period.key).to_query.merge(link_param)),
            active: period.key == query.period.key
          }
        end
      end

      def site_options
        sites.map do |candidate|
          {
            label: "#{candidate.name} (#{candidate.domain})",
            url: surface.path(query.to_query.merge(slice_param).merge(tag_param).merge(site: candidate.id)),
            active: candidate.id == site&.id
          }
        end
      end

      def range_label
        query.period.custom? ? query.range_label : query.period.label
      end

      def show_sites?
        sites.many?
      end

      def show_tags?
        surface&.group == "Rank tracking" && tag_menu.show?
      end

      def tag_menu
        memo(:tag_menu) do
          Serp::TagMenu.new(tags: @tags, current: tag,
                            url: ->(chosen) { surface.path(query.to_query.merge(site_param).merge(tag: chosen).compact) })
        end
      end

      def hub_path
        routes.seo_path(query.to_query)
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

      def sites_path
        routes.settings_serp_sites_path
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
        return slice_empty(title) if slice.any?

        SearchConsoleEmptyState.call(query: query, context: search_console_context, routes: routes, title: title, hint: hint,
                                     path: ->(overrides) { surface.path(query.with(overrides).to_query.merge(link_param)) })
      end

      def narrow?
        !AhoyDashboard::SeoRange.wide_enough?(query)
      end

      def widen_action
        { label: AhoyDashboard::SeoRange.widen_label, data: TOP, primary: true,
          url: surface.path(AhoyDashboard::SeoRange.widened(query).merge(link_param)) }
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

      # Formatting, in one place, because a percentage rounded two ways on two
      # cards of the same page is the fastest way to make a number look wrong.
      def percent(value, places: 0)
        "#{(value.to_f * 100).round(places)}%"
      end

      def number(value)
        ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      def decimal(value, places: 1)
        value.nil? ? DASH : value.to_f.round(places).to_s
      end

      def money(value)
        ActiveSupport::NumberHelper.number_to_currency(value.to_f)
      end

      def bytes(value)
        ActiveSupport::NumberHelper.number_to_human_size(value.to_i)
      end

      def when_label(time)
        time.nil? ? "Never" : "#{helpers.time_ago_in_words(time).delete_prefix("about ")} ago"
      end

      def on_label(date)
        AhoyDashboard::SeoHelper.short_date(date, zone: time_zone)
      end

      def local_date(value)
        AhoyDashboard::SeoHelper.local_date(value, zone: time_zone)
      end

      def signed(value, places: 0)
        return DASH if value.nil?

        rounded = places.zero? ? value.to_i : value.to_f.round(places)
        return "level" if rounded.zero?

        "#{rounded.positive? ? "+" : ""}#{rounded}"
      end

      def tone_for(value)
        return nil if value.nil? || value.to_f.zero?

        value.to_f.positive? ? :good : :bad
      end

      # A position moving down the page is a bad thing whose number went up, so
      # everything about rank inverts. Kept here rather than remembered on each
      # page, because getting it backwards once is a page that reads as good news.
      def rank_tone(change)
        return nil if change.nil? || change.zero?

        change.positive? ? "up" : "down"
      end

      def truncate(value, length: 60)
        value.to_s.truncate(length)
      end

      def path_of(url)
        return DASH if url.blank?

        url.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
      end

      def pluralize(count, word)
        helpers.pluralize(count, word)
      end

      private

      attr_reader :search_console_context

      def time_zone
        memo(:time_zone) { AhoyDashboard.time_zone }
      end

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

      def slice_empty(title)
        { title: title,
          hint: slice.empty_hint,
          action: { label: "Show all devices and countries", data: TOP, primary: true,
                    url: surface.path(query.to_query.merge(site_param)) } }
      end

      def memo(name)
        @memo ||= {}
        return @memo[name] if @memo.key?(name)

        @memo[name] = yield
      end

      def helpers
        ActionController::Base.helpers
      end

      def routes
        AhoyDashboard::Engine.routes.url_helpers
      end
    end
  end
end
