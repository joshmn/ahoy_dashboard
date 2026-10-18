module AhoyDashboard
  module Places
    class SearchQuery < AhoyDashboard::Query
      LIMIT = 40

      ROOT_LIMIT = 300
      BRANCH_LIMIT = 400
      LISTING_LIMIT = 60
      MIN_TERM = 2

      Result = Data.define(:places, :more) do
        def any?
          places.any?
        end

        def empty?
          places.empty?
        end
      end

      def initialize(parent: nil, term: nil, countries: nil, limit: nil)
        @parent = parent
        @term = term.to_s.strip
        @countries = countries
        @limit = limit
      end

      def call
        cap = limit
        rows = scope.limit(cap + 1).to_a

        Result.new(places: rows.first(cap), more: rows.size > cap)
      end

      private

      def limit
        return @limit if @limit
        return LIMIT if searching?
        return ROOT_LIMIT if @parent.nil?
        return BRANCH_LIMIT if @parent.country?

        LISTING_LIMIT
      end

      def scope
        searching? ? matches : listing
      end

      def searching?
        @term.length >= MIN_TERM
      end

      def listing
        return Place.children_of(@parent.code).ordered if @parent

        roots
      end

      def roots
        scope = Place.roots.order(:label, :code)
        scope = scope.where(country_code: @countries) if @countries.present?
        scope
      end

      def matches
        words = @term.downcase.split(/\s+/)
        scope = within.where("lower(#{Place.quoted_table_name}.label) like ?", "#{Place.sanitize_sql_like(words.first)}%")

        words.drop(1).each do |word|
          scope = scope.where("lower(#{Place.quoted_table_name}.name) like ?", "%,#{Place.sanitize_sql_like(word)}%")
        end

        scope.order(:depth, Arel.sql("length(#{Place.quoted_table_name}.label)"), :label, :code)
      end

      def within
        return Place.all if @parent.nil?

        Place.in_country(@parent.country_code)
          .where("#{Place.quoted_table_name}.name like ?", "%#{Place.sanitize_sql_like(Place::SEPARATOR + @parent.name)}")
          .where(Place.arel_table[:depth].gt(@parent.depth))
      end
    end
  end
end
