module AhoyDashboard
  module Seo
    class BrandSplitPresenter < BasePresenter
      def tracking_phrases
        (brand.terms + other.terms).map(&:query)
      end

      def tiles
        [
          Tile.new(label: "Clicks", value: number(result.clicks), note: "Google's total for the range", tone: nil),
          Tile.new(label: "Brand", value: number(result.brand.clicks), note: share_note(result.brand.clicks), tone: nil),
          Tile.new(label: "Non-brand", value: number(result.other.clicks), note: share_note(result.other.clicks), tone: nil),
          Tile.new(label: "Not named by Google", value: number(result.unnamed_clicks), note: share_note(result.unnamed_clicks), tone: nil),
          Tile.new(label: "Brand CTR", value: matched? ? percent(result.brand.ctr, places: 1) : nil, note: nil, tone: nil),
          Tile.new(label: "Non-brand CTR", value: other? ? percent(result.other.ctr, places: 1) : nil, note: nil, tone: nil)
        ]
      end

      def terms
        result.terms
      end

      def terms_text
        terms.join(", ")
      end

      def stored_terms?
        BrandTerms.stored?
      end

      def pattern
        result.pattern
      end

      def matched?
        result.matched?
      end

      def other?
        result.other.terms.any?
      end

      def unnamed?
        result.unnamed_clicks.positive?
      end

      def unnamed_clicks
        result.unnamed_clicks
      end

      def clicks
        result.clicks
      end

      def brand_points
        result.points.map { |point| [ on_label(point.on), point.brand_clicks ] }
      end

      def other_points
        result.points.map { |point| [ on_label(point.on), point.other_clicks ] }
      end

      def brand
        result.brand
      end

      def other
        result.other
      end

      def csv_tables
        [
          CsvTable.new(key: "brand", label: "Brand searches", headers: [ "Search", "Position", "Clicks" ]) do
            brand.terms.map { |term| [ term.query, term.position, term.clicks ] }
          end,
          CsvTable.new(key: "other", label: "Non-brand searches", headers: [ "Search", "Position", "Clicks" ]) do
            other.terms.map { |term| [ term.query, term.position, term.clicks ] }
          end
        ]
      end

      def terms_form_path
        routes.seo_brand_terms_path(query.to_query.merge(slice_param))
      end

      def clicks_hint(side)
        "#{pluralize(number(side.clicks), "click")}, average position #{decimal(side.position)}"
      end

      def clicks_label(count)
        pluralize(number(count), "click")
      end

      def last_date
        totals.last_date
      end

      def no_brand_hint
        return "Add your brand words above to split the searches." if terms.empty?

        "Nothing in this range contains #{terms.map { |term| "\"#{term}\"" }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}. Add another spelling of your name above."
      end

      private

      def share_note(count)
        result.clicks.zero? ? "no clicks in this range" : "#{percent(result.share_of(count))} of clicks"
      end
    end
  end
end
