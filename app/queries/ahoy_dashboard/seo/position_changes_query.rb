module AhoyDashboard
  module Seo
    class PositionChangesQuery
      MOVEMENTS = %i[gained lost improved declined level].freeze

      Row = Data.define(:keyword, :location, :from, :to, :url, :first_at, :last_at) do
        include Serp::Placed

        def query
          keyword.query
        end

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
        edges.group_by { |check| [ check.keyword_id, check.location ] }.map do |(_keyword_id, location), checks|
          first = checks.find { |check| check.id == check[:opening_id] }
          last = checks.find { |check| check.id == check[:closing_id] }

          Row.new(keyword: last.keyword, location: location, from: first.position, to: last.position, url: last.url,
                  first_at: first.checked_at, last_at: last.checked_at)
        end
      end

      def edges
        table = AhoyDashboard::SerpCheck.table_name
        window = "partition by keyword_id, location order by checked_at, id " \
                 "rows between unbounded preceding and unbounded following"
        ranked = AhoyDashboard::SerpCheck.success.where(site_id: site.id)
          .in_range(range)
          .for_tag(tag)
          .at_current_places
          .select("#{table}.*", "first_value(#{table}.id) over (#{window}) as opening_id",
                  "last_value(#{table}.id) over (#{window}) as closing_id")

        AhoyDashboard::SerpCheck.from(ranked, table)
          .where("#{table}.id in (opening_id, closing_id)")
          .order(:keyword_id, :location, :checked_at, :id)
          .includes(:keyword)
      end
    end
  end
end
