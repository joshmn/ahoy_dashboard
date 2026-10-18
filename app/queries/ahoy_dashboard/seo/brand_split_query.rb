module AhoyDashboard
  module Seo
    class BrandSplitQuery
      TERMS_PER_SIDE = 15

      Point = Data.define(:on, :brand_clicks, :other_clicks, :brand_impressions, :other_impressions) do
        def clicks
          brand_clicks + other_clicks
        end

        def share
          clicks.zero? ? 0.0 : brand_clicks.to_f / clicks
        end
      end

      Side = Data.define(:name, :clicks, :impressions, :position, :terms) do
        def ctr
          impressions.zero? ? 0.0 : clicks.to_f / impressions
        end
      end

      Term = Data.define(:query, :clicks, :impressions, :position)

      Result = Data.define(:range, :terms, :points, :brand, :other, :property_clicks) do
        def any?
          points.any?
        end

        def named_clicks
          brand.clicks + other.clicks
        end

        def clicks
          [ property_clicks.to_i, named_clicks ].max
        end

        def unnamed_clicks
          clicks - named_clicks
        end

        def share_of(count)
          clicks.zero? ? 0.0 : count.to_f / clicks
        end

        def pattern
          terms.join(", ")
        end

        def impressions
          brand.impressions + other.impressions
        end

        def matched?
          brand.clicks.positive? || brand.impressions.positive?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, terms: nil, slice: AhoyDashboard::SearchConsole::Slice.new, property_totals: nil)
        @range = range
        @slice = slice
        @property_totals = property_totals
        @terms = Array(terms).map(&:to_s).reject(&:blank?).presence || BrandTerms.current
      end

      def call
        Result.new(range: range, terms: terms, points: points,
                   brand: side("Brand", true), other: side("Everything else", false),
                   property_clicks: property_totals.clicks)
      end

      private

      attr_reader :range, :terms, :slice

      def property_totals
        @property_totals ||= PropertyTotalsQuery.call(range: range, slice: slice)
      end

      def matchers
        terms.map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(BrandTerms.fold(term))}%" }.uniq
      end

      def folded
        "regexp_replace(lower(query), '[[:space:]-]+', '', 'g')"
      end

      def matching
        Array.new(matchers.size, "#{folded} like ?").join(" or ")
      end

      def scope
        slice.apply(AhoyDashboard::SearchConsoleKeyword.in_range(range))
      end

      def classification
        @classification ||= Arel.sql(
          matchers.empty? ? "false::boolean" : AhoyDashboard::SearchConsoleKeyword.sanitize_sql_array([ matching, *matchers ])
        )
      end

      def daily_rows
        @daily_rows ||= scope.group(:date, classification).pluck(:date, classification, *SearchConsole::Sums::ALL)
      end

      def points
        both = daily_rows          .each_with_object({}) do |(on, brand, clicks, impressions), found|
            next if brand.nil?

            sides = found[on] ||= {}
            sides[brand] = [ clicks.to_i, impressions.to_i ]
          end

        both.sort.map do |on, sides|
          brand = sides[true] || [ 0, 0 ]
          other = sides[false] || [ 0, 0 ]

          Point.new(on: on, brand_clicks: brand.first, other_clicks: other.first,
                    brand_impressions: brand.last, other_impressions: other.last)
        end
      end

      def leading
        @leading ||= begin
          ranked = scope.group(:query, classification).select(
            "query", "#{classification} AS branded", "#{SearchConsole::Sums::CLICKS} AS clicks",
            "#{SearchConsole::Sums::IMPRESSIONS} AS impressions", "#{SearchConsole::Sums::POSITION} AS position",
            "row_number() over (partition by #{classification} order by #{SearchConsole::Sums::RANKING}, query) AS side_rank"
          )

          AhoyDashboard::SearchConsoleKeyword.from(ranked, :leading_terms)
            .where("side_rank <= ?", TERMS_PER_SIDE).order(:side_rank)
            .pluck(Arel.sql("branded, query, clicks, impressions, position"))
            .group_by(&:first)
        end
      end

      def terms_for(branded)
        leading.fetch(branded, []).map do |_branded, query, clicks, impressions, position|
          Term.new(query: query, clicks: clicks.to_i, impressions: impressions.to_i, position: position.to_f.round(1))
        end
      end

      def side(name, branded)
        readings = daily_rows.select { |row| row[1] == branded }
        totals = SearchConsole::Totals.from(clicks: readings.sum { |row| row[2].to_i },
                                            impressions: readings.sum { |row| row[3].to_i },
                                            weight: readings.sum { |row| row[4].to_f }, places: 1)

        Side.new(name: name, clicks: totals.clicks, impressions: totals.impressions, position: totals.position,
                 terms: terms_for(branded))
      end
    end
  end
end
