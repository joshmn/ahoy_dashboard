module AhoyDashboard
  module Serp
    class KeywordSeriesQuery
      Point = Data.define(:at, :position, :url, :overview, :cited)

      Result = Data.define(:keyword, :site, :range, :location, :locations, :points, :current,
                           :previous, :best, :worst, :run) do
        def any?
          points.any?
        end

        def ranked
          points.select(&:position)
        end

        def position
          current&.position
        end

        def change
          return nil if position.nil? || previous&.position.nil?

          previous.position - position
        end

        def place
          Location.parse(location)
        end

        def overviews
          points.count { |point| point.overview }
        end

        def citations
          points.count { |point| point.cited }
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(keyword:, site:, range:, location: nil)
        @keyword = keyword
        @site = site
        @range = range
        @location = location
      end

      def call
        checks = rows

        Result.new(
          keyword: keyword, site: site, range: range, location: chosen, locations: keyword.locations,
          points: checks.map { |check| point(check) }, current: checks.last, previous: checks[-2],
          best: checks.map(&:position).select { |value| value }.min, worst: checks.map(&:position).select { |value| value }.max,
          run: checks.last&.run
        )
      end

      private

      attr_reader :keyword, :site, :range, :location

      def chosen
        @chosen ||= keyword.locations.include?(location.to_s) ? location.to_s : keyword.locations.first
      end

      def rows
        return [] if site.nil?

        SerpCheck.where(keyword_id: keyword.id, site_id: site.id, location: chosen,
                        status: SerpCheck.statuses[:success])
          .in_range(range)
          .chronological
          .to_a
      end

      def point(check)
        Point.new(at: check.checked_at, position: check.position, url: check.url,
                  overview: check.ai_overview_present.present?,
                  cited: check.ai_overview_cited.present?)
      end
    end
  end
end
