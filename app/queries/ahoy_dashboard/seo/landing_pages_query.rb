module AhoyDashboard
  module Seo
    class LandingPagesQuery
      Held = Data.define(:keyword, :query, :location, :position) do
        def place
          Serp::Location.parse(location)
        end
      end

      Gone = Data.define(:keyword, :query, :location, :was, :now_url, :now_position) do
        def place
          Serp::Location.parse(location)
        end

        def ranked_elsewhere?
          now_position.present?
        end
      end

      Page = Data.define(:url, :held, :points, :share) do
        def searches
          held.size
        end

        def best
          held.map(&:position).min
        end

        def median
          positions = held.map(&:position).sort
          middle = positions.size / 2
          return positions[middle] if positions.size.odd?

          ((positions[middle - 1] + positions[middle]) / 2.0).round(1)
        end
      end

      Lost = Data.define(:url, :gone) do
        def searches
          gone.size
        end
      end

      Result = Data.define(:site, :range, :pages, :lost, :tracked, :points) do
        def any?
          pages.any? || lost.any?
        end

        def held
          pages.sum(&:searches)
        end

        def unheld
          tracked - held
        end

        def top
          pages.first
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, tag: nil)
        @site = site
        @range = range
        @tag = tag
      end

      def call
        return Result.new(site: site, range: range, pages: [], lost: [], tracked: 0, points: 0.0) if site.nil?

        Result.new(site: site, range: range, pages: pages, lost: lost, tracked: latest.size, points: total_points)
      end

      private

      attr_reader :site, :range, :tag

      def checks
        AhoyDashboard::SerpCheck
          .where(site_id: site.id, status: AhoyDashboard::SerpCheck.statuses[:success])
          .in_range(range).for_tag(tag)
      end

      def latest
        @latest ||= checks.select("DISTINCT ON (keyword_id, location) ahoy_dashboard_serp_checks.*")
          .reorder(:keyword_id, :location, checked_at: :desc, id: :desc).includes(:keyword)
          .each_with_object({}) { |check, found| found[[check.keyword_id, check.location]] = check }
      end

      def earlier
        relation = checks.where.not(position: nil).where("url ~ '[^[:space:]]'")
        relation = relation.where.not(url: pages.map(&:url)) if pages.any?
        relation.select("DISTINCT ON (url, keyword_id, location) ahoy_dashboard_serp_checks.*")
          .reorder(:url, :keyword_id, :location, checked_at: :desc, id: :desc).includes(:keyword)
          .group_by(&:url)
      end

      def total_points
        @total_points ||= latest.values.sum { |check| CtrCurve.at(check.position) }
      end

      def holding?(check)
        check.position.present? && check.url.present?
      end

      def pages
        @pages ||= latest.values.select { |check| holding?(check) }.group_by(&:url).map do |url, checks|
          points = checks.sum { |check| CtrCurve.at(check.position) }
          held = checks.map do |check|
            Held.new(keyword: check.keyword, query: check.keyword.query, location: check.location, position: check.position)
          end

          Page.new(url: url, held: held.sort_by { |row| [ row.position, row.query ] }, points: points,
                   share: total_points.zero? ? 0.0 : points / total_points)
        end.sort_by { |page| [ -page.points, -page.searches, page.best, page.url ] }
      end

      def lost
        earlier.map do |url, held|
          gone = held.map do |was|
            location = was.location
            now = latest[[ was.keyword_id, location ]]

            Gone.new(keyword: was.keyword, query: was.keyword.query, location: location, was: was.position,
                     now_url: (now.url if holding?(now)), now_position: (now.position if holding?(now)))
          end

          Lost.new(url: url, gone: gone.sort_by { |row| [ row.was, row.query ] })
        end.sort_by { |page| [ -page.searches, page.url ] }
      end
    end
  end
end
