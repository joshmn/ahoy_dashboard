module AhoyDashboard
  module Serp
    class KeywordPresenter
      include AhoyDashboard::Seo::Exportable

      EXPORT_KEY = "rank-keyword".freeze

      Tile = Data.define(:label, :value, :note)

      attr_reader :query, :result, :share

      def initialize(query:, result:, share: nil)
        @query = query
        @result = result
        @share = share
      end

      def keyword
        result.keyword
      end

      def heading
        keyword.query
      end

      def site
        result.site
      end

      def empty?
        !result.any?
      end

      def summary
        parts = [ result.place.label, range_label.downcase ]
        parts << "#{helpers.pluralize(result.points.size, 'reading')}"
        parts << "for #{site.name}, not your site" if site.present? && !site.ours?

        parts.join(" · ")
      end

      def source_line
        "Checked #{decorated_keyword.frequency_label.downcase}, #{keyword.pages} " \
          "#{"page".pluralize(keyword.pages)} deep, on #{keyword.device}."
      end

      def search_label
        decorated_keyword.search_label
      end

      def tiles
        [
          Tile.new(label: "Position", value: value_for(result.position), note: change_note),
          Tile.new(label: "Best", value: value_for(result.best), note: "in this range"),
          Tile.new(label: "Worst", value: value_for(result.worst), note: "in this range"),
          Tile.new(label: "AI overviews", value: result.overviews.to_s,
                   note: "#{result.citations} cited #{site&.domain}")
        ]
      end

      def value_for(position)
        position&.to_s
      end

      def change_note
        return "no reading before this" if result.change.nil?
        return "same as the reading before" if result.change.zero?

        "#{result.change.positive? ? "up" : "down"} #{result.change.abs} on the reading before"
      end

      def change_tone
        return nil if result.change.nil? || result.change.zero?

        result.change.positive? ? :good : :bad
      end

      def chart_kind
        :line
      end

      def chart_data
        return [] if result.ranked.empty?

        [ { name: "Position", data: points } ]
      end

      # A reading where the site was nowhere is not position zero and it is not a
      # missing check either, so it leaves a hole in the line rather than being
      # drawn at the bottom of the chart.
      def points
        result.points.map { |point| [ point.at.in_time_zone(zone).iso8601, point.position ] }
      end

      def readings
        result.ranked.map { |point| [ AhoyDashboard::SeoHelper.short_date(point.at, zone: zone), point.position ] }
      end

      def chart_options
        {
          library: {
            plugins: {
              tmFormat: { label: "Position", value: "integer", interval: "day", scale: "time",
                          missing: "Not in the results" }
            },
            scales: { y: { reverse: true } }
          }
        }
      end

      def rows
        result.points.reverse
      end

      def rivals
        return [] if result.run.nil?

        @rivals ||= result.run.results.ranked.first(Serp::RESULTS_PER_PAGE)
      end

      def rivals_note
        return nil if result.run.nil?

        "The top #{rivals.size} results from the check on #{stamp(result.run.checked_at)}."
      end

      def citations
        return [] if result.run.nil?

        @citations ||= AhoyDashboard::SerpAiCitation.where(run_id: result.run.id).order(:slot).to_a
      end

      def location_options
        result.locations.map do |value|
          {
            label: Location.parse(value).label,
            url: path(at: value),
            active: value == result.location
          }
        end
      end

      def search_options
        @search_options ||= SerpKeywordDecorator.wrap(
          SerpKeyword.phrased(keyword.query).order(:device, :language, :id)
        ).map do |candidate|
          {
            label: candidate.search_label,
            url: link_for(query.to_query, target: candidate),
            active: candidate.id == keyword.id
          }
        end
      end

      def period_options
        AhoyDashboard::SeoRange.periods.map do |period|
          {
            label: period.label,
            url: link_for(query.with(period: period.key).to_query),
            active: period.key == query.period.key
          }
        end
      end

      def range_label
        query.period.custom? ? query.range_label : query.period.label
      end

      def rankings_path
        routes.rankings_path(query.to_query.merge(site: site&.id))
      end

      def edit_path
        routes.edit_settings_serp_keyword_path(keyword)
      end

      def stamp(at)
        AhoyDashboard::SeoHelper.short_date(at.in_time_zone(zone), zone: zone)
      end

      def empty_title
        "Nothing recorded in this range"
      end

      def empty_hint
        return "This keyword has not been checked yet. Checks start within the hour." if
          keyword.last_checked_at.blank?

        "It was last checked #{stamp(keyword.last_checked_at)}, outside this range. Try a longer date range."
      end

      def ours?
        site&.ours?
      end

      def export_key
        EXPORT_KEY
      end

      def export_path(params)
        routes.rank_keyword_path(params)
      end

      def export_params
        query.to_query.merge(keyword: keyword.id, at: result.location, site: site&.id).compact
      end

      def csv_tables
        [
          AhoyDashboard::Seo::CsvTable.new(key: "readings", label: "Every reading",
                                           headers: [ "Checked", "Position", "AI", "URL" ]) do
            rows.map { |point| [ csv_time(point.at), point.position, overview_csv(point), url_csv(point.url) ] }
          end,
          AhoyDashboard::Seo::CsvTable.new(key: "rivals", label: "Who else ranked",
                                           headers: [ "Position", "Domain" ]) do
            rivals.map { |rival| [ rival.position, rival.domain ] }
          end,
          AhoyDashboard::Seo::CsvTable.new(key: "citations", label: "The AI overview",
                                           headers: [ "Slot", "Domain" ]) do
            citations.map { |citation| [ citation.slot, citation.domain ] }
          end
        ]
      end

      private

      def decorated_keyword
        @decorated_keyword ||= SerpKeywordDecorator.new(keyword)
      end

      def overview_csv(point)
        return "Cited" if point.cited
        return "Shown" if point.overview

        nil
      end

      def url_csv(url)
        return nil if url.blank?

        url.to_s.sub(%r{\Ahttps?://[^/]+}, "").presence || "/"
      end

      def zone
        @zone ||= AhoyDashboard.time_zone
      end

      def path(overrides = {})
        link_for(query.to_query.merge(overrides))
      end

      def link_for(params, target: keyword)
        routes.rank_keyword_path(
          { at: result.location, site: site&.id }.merge(params).merge(keyword: target.id).compact
        )
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
