module AhoyDashboard
  module Seo
    # What moved over the range, which is the thing a list of current positions
    # cannot tell you. Five buckets, and the two that matter most are the ones a
    # sorted position column hides: what arrived, and what fell out.
    #
    # First reading against last reading, not yesterday against today. A daily
    # diff on a set of searches that are re-checked weekly is mostly a list of
    # searches nobody looked at.
    class PositionChangesQuery
      MOVEMENTS = %i[gained lost improved declined level].freeze

      Row = Data.define(:keyword, :query, :location, :from, :to, :url, :first_at, :last_at) do
        def movement
          return :gained if from.nil? && to.present?
          return :lost if from.present? && to.nil?
          return :level if from == to
          return :improved if to < from

          :declined
        end

        def change
          return nil if from.nil? || to.nil?

          from - to
        end

        def ranked?
          to.present?
        end

        def onto_page_one?
          movement == :improved && to <= 10 && from > 10
        end

        def off_page_one?
          movement == :declined && from <= 10 && to > 10
        end

        def place
          Serp::Location.parse(location)
        end
      end

      Result = Data.define(:site, :range, :rows) do
        def any?
          rows.any?
        end

        def for(movement)
          rows.select { |row| row.movement == movement }
        end

        def count_of(movement)
          self.for(movement).size
        end

        def moved
          rows.reject { |row| row.movement == :level }
        end

        def improved
          self.for(:improved).sort_by { |row| -row.change.to_i }
        end

        def declined
          self.for(:declined).sort_by { |row| row.change.to_i }
        end

        def gained
          self.for(:gained).sort_by { |row| row.to.to_i }
        end

        def lost
          self.for(:lost).sort_by { |row| row.from.to_i }
        end

        def onto_page_one
          rows.select(&:onto_page_one?)
        end

        def off_page_one
          rows.select(&:off_page_one?)
        end

        # A range where nothing has two readings cannot answer this at all, and
        # saying so beats printing a page of "level".
        def comparable?
          rows.any? { |row| row.first_at != row.last_at }
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
        return Result.new(site: site, range: range, rows: []) if site.nil?

        Result.new(site: site, range: range, rows: rows)
      end

      private

      attr_reader :site, :range, :tag

      def rows
        opening = edge(:asc)
        closing = edge(:desc)
        keywords = AhoyDashboard::SerpKeyword.where(id: closing.keys.map(&:first).uniq).index_by(&:id)

        closing.map do |key, last|
          keyword = keywords[key.first]
          next if keyword.nil?

          first = opening[key] || last

          Row.new(keyword: keyword, query: keyword.query, location: key.last,
                  from: first.position, to: last.position, url: last.url,
                  first_at: first.checked_at, last_at: last.checked_at)
        end.select { |value| value }
      end

      def edge(direction)
        AhoyDashboard::SerpCheck
          .where(site_id: site.id, status: AhoyDashboard::SerpCheck.statuses[:success])
          .in_range(range)
          .for_tag(tag)
          .select("distinct on (keyword_id, location) ahoy_dashboard_serp_checks.*")
          .order(Arel.sql("keyword_id, location, checked_at #{direction == :asc ? "asc" : "desc"}, id #{direction == :asc ? "asc" : "desc"}"))
          .index_by { |check| [ check.keyword_id, check.location ] }
      end
    end
  end
end
