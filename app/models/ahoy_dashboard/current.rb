module AhoyDashboard
  class Current < ActiveSupport::CurrentAttributes
    attribute :exclusions, :tables, :preferences, :favicon_domains,
              :dimension_sql, :filterable_dimensions, :picker_facets

    class << self
      def forget_dimensions
        self.dimension_sql = nil
        self.filterable_dimensions = nil
        self.picker_facets = nil
      end
    end
  end
end
