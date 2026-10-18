module AhoyDashboard
  class DetailsSearchQuery
    class << self
      def condition(dimension:, term:)
        term = SearchTerm.clean(term)
        return if term.blank?

        ActiveRecord::Base.sanitize_sql_array(
          [ "#{dimension.sql} ilike :term", { term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" } ]
        )
      end
    end
  end
end
