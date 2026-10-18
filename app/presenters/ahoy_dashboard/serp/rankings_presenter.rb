module AhoyDashboard
  module Serp
    class RankingsPresenter < AhoyDashboard::Seo::BasePresenter
      BandItem = Data.define(:band, :count, :url, :current) do
        def key
          band.key
        end

        def label
          band.label
        end
      end

      TABLE_ANCHOR = "tracked-searches".freeze

      attr_reader :visibility, :share, :distribution, :band

      def initialize(visibility:, share:, distribution: nil, band: nil,
                     surface: AhoyDashboard::Seo::Surface.find("rankings"), **options)
        super(surface: surface, **options)
        @visibility = visibility
        @share = share
        @distribution = distribution
        @band = RankBand.find(band)
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

        movement(row.change)
      end

      def overview_label(row)
        return "Cited" if row.cited?

        "Shown" if row.overview?
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

      def widen_action
        super.merge(url: surface.path(AhoyDashboard::Seo::Periods.widened(query).merge(site_param).merge(tag_param)))
      end

      def empty_action
        return widen_action if narrow?

        tag_menu.clear_action(data: TOP) if tag
      end

      def empty_hint
        return "No check tagged #{tag} ran in these dates. Try a longer date range, or another tag." if tag
        return "No check ran in these dates. Try a longer date range, or press Check now." if check_now.available?

        "No check ran in these dates. Try a longer date range."
      end

      def tagging_path
        routes.rankings_tags_path
      end

      def return_to
        rankings_url(band: band&.key)
      end

      def check_now
        @check_now ||= CheckNowPresenter.new
      end

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
          "#{pluralize(share.searches, 'search')}."
      end

      def visibility_note
        return "No check has looked for an AI overview yet." unless visibility.any?

        "#{percent(visibility.share_shown)} of checks showed an AI overview, and " \
          "#{percent(visibility.share_cited)} of those cited #{site.domain}."
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

      private

      def link_param
        super.merge({ band: band&.key }.compact)
      end

      def tracked_headers
        headers = [ "Search", "Position", "Change", "Best", "AI", "URL" ]
        headers.insert(1, "Place") if places?

        headers
      end

      def tracked_csv_row(row)
        values = [ row.keyword.query, (row.position if row.ranked?), csv_change(row), row.best,
                   overview_label(row), AhoyDashboard::Seo::Formatting.url_path(row.url) ]
        values.insert(1, row.place.label) if places?

        values
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
        surface.path(query.to_query.merge(site_param).merge(tag_param).merge({ band: band, anchor: anchor }.compact))
      end
    end
  end
end
