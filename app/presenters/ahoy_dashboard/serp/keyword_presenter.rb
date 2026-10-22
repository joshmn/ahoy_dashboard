module AhoyDashboard
  module Serp
    class KeywordPresenter
      include AhoyDashboard::Seo::Exportable
      include AhoyDashboard::Seo::Formatting

      EXPORT_KEY = "rank-keyword".freeze

      Tile = AhoyDashboard::Seo::BasePresenter::Tile

      attr_reader :query, :result, :share

      delegate :keyword, :site, to: :result

      def initialize(query:, result:, share: nil)
        @query = query
        @result = result
        @share = share
      end

      def heading
        keyword.query
      end

      def empty?
        !result.any?
      end

      def summary
        parts = [ result.place.label, range_label.downcase ]
        parts << "#{pluralize(result.points.size, 'reading')}"
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
          Tile.new(label: "Position", value: result.position&.to_s, note: change_note),
          Tile.new(label: "Best", value: result.best&.to_s, note: "in this range"),
          Tile.new(label: "Worst", value: result.worst&.to_s, note: "in this range"),
          Tile.new(label: "AI overviews", value: result.overviews.to_s,
                   note: "#{result.citations} cited #{site&.domain}")
        ]
      end

      def change_note
        return "no reading before this" if result.change.nil?
        return "same as the reading before" if result.change.zero?

        "#{result.change.positive? ? "up" : "down"} #{result.change.abs} on the reading before"
      end

      def change_tone
        tone_for(result.change)
      end

      def chart_data
        return [] if result.ranked.empty?

        [ { name: "Position", data: points } ]
      end

      def points
        result.points.map { |point| [ point.at.in_time_zone(time_zone).iso8601, point.position ] }
      end

      def readings
        result.ranked.map { |point| [ on_label(point.at), point.position ] }
      end

      def chart_options
        {
          library: {
            tmFill: false,
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

        "The top #{rivals.size} results from the check on #{on_label(result.run.checked_at)}."
      end

      def citations
        return [] if result.run.nil?

        @citations ||= AhoyDashboard::SerpAiCitation.where(run_id: result.run.id).order(:slot).to_a
      end

      def mine?(domain)
        Domain.matches_site?(domain, site)
      end

      def overview_label(point)
        return "Cited" if point.cited

        "Shown" if point.overview
      end

      def check_now
        @check_now ||= CheckNowPresenter.new(keyword: keyword)
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
        AhoyDashboard::Seo::Periods.menu(query) { |period| link_for(query.with(period: period.key).to_query) }
      end

      def range_label
        query.range_title
      end

      def rankings_path
        routes.rankings_path(query.to_query.merge(site: site&.id))
      end

      def edit_path
        routes.edit_settings_serp_keyword_path(keyword)
      end

      def stamp(at)
        on_label(at)
      end

      def empty_title
        "Nothing recorded in this range"
      end

      def empty_hint
        return "This keyword has not been checked yet. Checks start within the hour." if
          keyword.last_checked_at.blank?

        "It was last checked #{stamp(keyword.last_checked_at)}, outside this range. Try a longer date range."
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
            rows.map do |point|
              [ csv_time(point.at), point.position, overview_label(point), AhoyDashboard::Seo::Formatting.url_path(point.url) ]
            end
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

      def path(overrides = {})
        link_for(query.to_query.merge(overrides))
      end

      def link_for(params, target: keyword)
        routes.rank_keyword_path(
          { at: result.location, site: site&.id }.merge(params).merge(keyword: target.id).compact
        )
      end

      def routes
        AhoyDashboard.routes
      end
    end
  end
end
