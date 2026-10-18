module AhoyDashboard
  module SearchConsole
    Totals = Data.define(:clicks, :impressions, :ctr, :position) do
      class << self
        def from(clicks:, impressions:, weight:, places: nil)
          clicks = clicks.to_i
          impressions = impressions.to_i
          return new(clicks: clicks, impressions: impressions, ctr: 0.0, position: 0.0) unless impressions.positive?

          position = weight.to_f / impressions

          new(clicks: clicks, impressions: impressions, ctr: clicks.to_f / impressions,
              position: places ? position.round(places) : position)
        end
      end

      def any?
        clicks.positive? || impressions.positive?
      end
    end
  end
end
