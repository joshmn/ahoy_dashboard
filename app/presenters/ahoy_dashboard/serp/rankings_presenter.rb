module AhoyDashboard
  module Serp
    class RankingsPresenter
      include AhoyDashboard::Seo::Exportable

      Tile = Data.define(:label, :value, :note)

      BandItem = Data.define(:band, :count, :url, :current) do
        def key
          band.key
        end

        def label
          band.label
        end
      end

      attr_reader :query, :result, :visibility, :share, :site, :sites, :distribution, :band, :tag, :tags

      def initialize(query:, result:, visibility:, share:, site:, sites:, distribution: nil, band: nil,
                     tag: nil, tags: [])
        @query = query
        @result = result
        @visibility = visibility
        @share = share
        @site = site
        @sites = sites
        @distribution = distribution
        @band = RankBand.find(band)
        @tag = tag.presence
        @tags = tags
      end

      def heading
        rival? ? "Rankings: #{site.name}" : "Rankings"
      end

      def surface
        @surface ||= AhoyDashboard::Seo::Surface.find("rankings")
      end

      def blurb
        rival? ? surface.blurb.sub("your site", site.name) : surface.blurb
      end

      def rival?
        site.present? && !site.ours?
      end

      def site_label
        "Site: #{site&.name || "none"}"
      end

      def any?
        result.any?
      end

      def rows
        @rows ||= band ? result.rows.select { |row| band.covers?(row.position) } : result.rows
      end

      def band_items
        RankBand::ALL.map do |candidate|
          current = candidate == band

          BandItem.new(band: candidate, count: distribution.count(candidate.key), current: current,
                       url: rankings_url(band: (candidate.key unless current), anchor: TABLE_ANCHOR))
        end
      end

      def band_label
        band_items.map { |item| "#{item.label}: #{number(item.count)}" }.join(", ")
      end

      def distribution_label
        latest = distribution.latest
        return "No readings in this range" if latest.nil?

        "Tracked searches by position band, one bar per day. On #{on_label(latest.date)}, #{band_label}."
      end

      def day_title(day)
        counts = RankBand::ALL.map { |candidate| "#{candidate.label}: #{number(day.count(candidate.key))}" }

        "#{on_label(day.date)}. #{counts.join(', ')}"
      end

      def distribution_dates
        days = distribution.days
        return [] if days.empty?

        [ on_label(days.first.date), (on_label(days.last.date) if days.many?) ].compact
      end

      def band_note
        return nil if band.nil?

        "Showing #{band.label} only"
      end

      def all_bands_url
        rankings_url(band: nil, anchor: TABLE_ANCHOR)
      end

      def band_empty_title
        "Nothing in #{band&.label} on the latest reading"
      end

      TABLE_ANCHOR = "tracked-searches".freeze

      def no_site?
        site.nil?
      end

      def no_keywords?
        SerpKeyword.none?
      end

      def setup_notice
        return @setup_notice if defined?(@setup_notice)

        @setup_notice =
          if no_site? then AhoyDashboard::SetupNotice.call(:site, url: new_site_path)
          elsif no_keywords? then AhoyDashboard::SetupNotice.call(:keywords, url: new_keyword_path)
          end
      end

      def summary
        return "Nothing is being tracked yet." if no_keywords?
        return "No site is set up to look for." if no_site?

        "#{site.domain} · #{range_label.downcase} · #{helpers.pluralize(result.tracked, 'search')}"
      end

      def tiles
        [
          Tile.new(label: "Searches", value: number(result.tracked), note: "keyword and place pairs"),
          Tile.new(label: "Ranking", value: number(result.ranked), note: percent(result.share(result.ranked))),
          Tile.new(label: "Top ten", value: number(result.top_ten), note: percent(result.share(result.top_ten))),
          Tile.new(label: "Top three", value: number(result.top_three), note: percent(result.share(result.top_three))),
          Tile.new(label: "Median position", value: result.median&.to_s, note: "of the ones ranking"),
          Tile.new(label: "AI overviews", value: number(result.overviews), note: cited_note)
        ]
      end

      def cited_note
        return "none showed one" if result.overviews.zero?

        "#{number(result.cited)} cite #{site.domain}"
      end

      def change_kind(row)
        return :new if row.arrived?
        return :gone if row.lost?
        return :none if row.change.nil?
        return :level if row.change.zero?

        row.change.positive? ? :up : :down
      end

      def places?
        return @places if defined?(@places)

        @places = rows.map { |row| row.place.label }.uniq.many?
      end

      def table_cols
        [ "34px", "minmax(0, 1.5fr)", ("112px" if places?), "76px", "96px", "56px", "72px", "minmax(0, 1fr)" ].compact.join(" ")
      end

      def position_label(row)
        return row.position.to_s if row.ranked?

        depth = row.current&.run&.requested_pages.to_i * Serp::RESULTS_PER_PAGE

        depth.positive? ? "Past #{depth}" : "Nowhere"
      end

      def keyword_path(row)
        routes.rank_keyword_path(query.to_query.merge(keyword: row.keyword.id, at: row.location, site: site&.id).compact)
      end

      def site_options
        sites.map do |candidate|
          {
            label: "#{candidate.name} (#{candidate.domain})",
            url: routes.rankings_path(query.to_query.merge(site: candidate.id, band: band&.key, tag: tag).compact),
            active: candidate.id == site&.id
          }
        end
      end

      def period_options
        AhoyDashboard::SeoRange.periods.map do |period|
          {
            label: period.label,
            url: routes.rankings_path(query.with(period: period.key).to_query.merge(site: site&.id, band: band&.key, tag: tag).compact),
            active: period.key == query.period.key
          }
        end
      end

      def range_label
        query.period.custom? ? query.range_label : query.period.label
      end

      def widen_action
        return nil if AhoyDashboard::SeoRange.wide_enough?(query)

        { label: AhoyDashboard::SeoRange.widen_label, primary: true, data: { tm_frame: "_top" },
          url: routes.rankings_path(AhoyDashboard::SeoRange.widened(query).merge(site: site&.id, tag: tag).compact) }
      end

      def tag_menu
        @tag_menu ||= TagMenu.new(
          tags: tags, current: tag,
          url: ->(chosen) { routes.rankings_path(query.to_query.merge(site: site&.id, band: band&.key, tag: chosen).compact) }
        )
      end

      def empty_action
        widen_action || (tag_menu.clear_action(data: { tm_frame: "_top" }) if tag)
      end

      def empty_hint
        return "No check tagged #{tag} ran in these dates. Try a longer date range, or another tag." if tag
        return "No check ran in these dates. Try a longer date range, or press Check now." if check_now?

        "No check ran in these dates. Try a longer date range."
      end

      def tagging_path
        routes.rankings_tags_path
      end

      def return_to
        rankings_url(band: band&.key)
      end

      def dashboard_path
        routes.root_path(query.to_query)
      end

      def check_now_path
        check_now.path
      end

      def trackable
        @trackable ||= SerpKeyword.trackable.to_a
      end

      def check_now?
        check_now.available?
      end

      def check_now_reason
        check_now.reason
      end

      def check_now_notice_reason
        check_now.notice_reason
      end

      def check_now_fix
        check_now.fix
      end

      def check_now_confirm
        check_now.confirm
      end

      def keywords_path
        routes.settings_serp_keywords_path
      end

      def invented?
        Serp.provider.to_sym == :fake
      end

      def providers_path
        routes.settings_serp_providers_path
      end

      def new_keyword_path
        routes.new_settings_serp_keyword_path
      end

      def new_site_path
        routes.new_settings_serp_site_path
      end

      SHARE_FLOOR = 3

      def shares?
        share.searches.to_i >= SHARE_FLOOR
      end

      def cited_shares?
        visibility.shown.to_i >= SHARE_FLOOR
      end

      def share_cols
        shares? ? "minmax(0, 1fr) 80px 104px 56px" : "minmax(0, 1fr) 80px 56px"
      end

      def cited_cols
        cited_shares? ? "minmax(0, 1fr) 80px 104px" : "minmax(0, 1fr) 80px"
      end

      def share_floor_note
        "Share shows once #{SHARE_FLOOR} searches are behind it. Out of fewer, every site reads close to 100%."
      end

      def share_note
        return nil unless share.any?

        "Sites in the top #{share.depth} results, from the latest check of " \
          "#{helpers.pluralize(share.searches, 'search')}."
      end

      def visibility_note
        return "No check has looked for an AI overview yet." unless visibility.any?

        "#{percent(visibility.share_shown)} of checks showed an AI overview, and " \
          "#{percent(visibility.share_cited)} of those cited #{site.domain}."
      end

      def export_key
        surface.export
      end

      def export_path(params)
        routes.rankings_path(params)
      end

      def export_params
        query.to_query.merge(site: site&.id, band: band&.key, tag: tag).compact
      end

      def csv_tables
        [
          AhoyDashboard::Seo::CsvTable.new(key: "tracked_searches", label: "Tracked searches",
                                           headers: tracked_headers) { rows.map { |row| tracked_csv_row(row) } },
          AhoyDashboard::Seo::CsvTable.new(key: "page_one", label: "Who else is on page one",
                                           headers: page_one_headers) { share.rows.map { |row| page_one_csv_row(row) } },
          AhoyDashboard::Seo::CsvTable.new(key: "ai_overviews", label: "AI overviews",
                                           headers: overview_headers) { visibility.domains.map { |row| overview_csv_row(row) } }
        ]
      end

      def percent(value)
        "#{(value.to_f * 100).round}%"
      end

      def number(value)
        ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      private

      def tracked_headers
        headers = [ "Search", "Position", "Change", "Best", "AI", "URL" ]
        headers.insert(1, "Place") if places?

        headers
      end

      def tracked_csv_row(row)
        values = [ row.keyword.query, (row.position if row.ranked?), change_csv(row), row.best,
                   overview_csv(row), url_csv(row.url) ]
        values.insert(1, row.place.label) if places?

        values
      end

      def change_csv(row)
        case change_kind(row)
        when :new then "New"
        when :gone then "Gone"
        else row.change
        end
      end

      def overview_csv(row)
        return "Cited" if row.cited?
        return "Shown" if row.overview?

        nil
      end

      def url_csv(url)
        return nil if url.blank?

        url.to_s.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
      end

      def page_one_headers
        headers = [ "Domain", "Searches", "Best" ]
        headers.insert(2, "Share") if shares?

        headers
      end

      def page_one_csv_row(row)
        values = [ row.domain, row.appearances, row.best ]
        values.insert(2, csv_percent(row.share)) if shares?

        values
      end

      def overview_headers
        headers = [ "Cited domain", "Citations" ]
        headers << "Share" if cited_shares?

        headers
      end

      def overview_csv_row(row)
        values = [ row.domain, row.citations ]
        values << csv_percent(row.share) if cited_shares?

        values
      end

      def rankings_url(band:, anchor: nil)
        routes.rankings_path(query.to_query.merge(site: site&.id, band: band, tag: tag, anchor: anchor).compact)
      end

      def on_label(date)
        AhoyDashboard::SeoHelper.short_date(date, zone: (@zone ||= AhoyDashboard.time_zone))
      end

      def check_now
        @check_now ||= CheckNowPresenter.new
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
