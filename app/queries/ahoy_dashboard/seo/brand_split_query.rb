module AhoyDashboard
  module Seo
    # People who already knew the name, kept apart from people who did not.
    #
    # Worth doing because the two move for completely different reasons and a
    # combined line hides both. Brand search follows whatever else is going on:
    # a mention somewhere, a mailout, somebody being talked about. Everything
    # else is the part any of this work is actually trying to move. Pooled
    # together, a good week of brand traffic can cover a bad month of the rest.
    class BrandSplitQuery
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

        def brand_share
          share_of(brand.clicks)
        end

        def matched?
          brand.clicks.positive? || brand.impressions.positive?
        end
      end

      def self.call(**options)
        new(**options).call
      end

      # The pattern is a guess off the host until somebody says otherwise, which
      # is right often enough to be useful and wrong often enough that it has to
      # be editable on the page. A site called after a common word cannot be
      # split this way at all and the page has to be able to say so.
      def initialize(range:, terms: nil, slice: AhoyDashboard::SearchConsole::Slice.new, property_totals: nil)
        @range = range
        @slice = slice
        @property_totals = property_totals
        @terms = Array(terms).map(&:to_s).reject(&:blank?).presence || BrandTerms.current
      end

      def call
        Result.new(range: range, terms: terms, points: points,
                   brand: side("Brand", brand_rows), other: side("Everything else", other_rows),
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

      def branded
        matchers.empty? ? scope.none : scope.where(matching, *matchers)
      end

      def unbranded
        matchers.empty? ? scope : scope.where.not(matching, *matchers)
      end

      def daily_rows
        @daily_rows ||= begin
          predicate = matchers.empty? ? "false::boolean" : AhoyDashboard::SearchConsoleKeyword.sanitize_sql_array([matching, *matchers])
          classification = Arel.sql(predicate)
          scope.group(:date, classification)
            .pluck(:date, classification, Arel.sql("sum(clicks)"), Arel.sql("sum(impressions)"),
                   Arel.sql("sum(position * impressions)"))
        end
      end

      def points
        both = daily_rows          .each_with_object({}) do |(on, brand, clicks, impressions), found|
            # SQL WHERE matching and WHERE NOT matching both omit NULL.
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

      def brand_rows
        rows_for(branded)
      end

      def other_rows
        rows_for(unbranded)
      end

      def rows_for(relation)
        relation.group(:query)
          .select(
            "query",
            "sum(clicks) as clicks",
            "sum(impressions) as impressions",
            "sum(position * impressions) / nullif(sum(impressions), 0) as position"
          )
          .order(Arel.sql("sum(clicks) desc, sum(impressions) desc"))
          .limit(15)
          .map { |row| Term.new(query: row.query, clicks: row.clicks.to_i, impressions: row.impressions.to_i, position: row.position.to_f.round(1)) }
      end

      def side(name, rows)
        readings = daily_rows.select { |row| row[1] == (name == "Brand") }
        clicks = readings.sum { |row| row[2].to_i }
        impressions = readings.sum { |row| row[3].to_i }
        weight = readings.sum { |row| row[4].to_f }
        position = impressions.zero? ? 0.0 : (weight / impressions).round(1)

        Side.new(name: name, clicks: clicks, impressions: impressions, position: position, terms: rows)
      end
    end
  end
end
