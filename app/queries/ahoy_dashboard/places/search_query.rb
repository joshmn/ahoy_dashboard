module AhoyDashboard
  module Places
    # One step of the place picker: the list at a point in the tree, or what a
    # typed term matches.
    #
    # Typing searches from wherever the picker is standing rather than from the
    # top. Somebody who has opened Illinois and typed "spring" wants Springfield,
    # Illinois, not the eleven other Springfields. The whole path is stored on
    # every row, so a descendant is a suffix match and needs no recursion.
    class SearchQuery
      LIMIT = 40

      # Browsing is not searching, and a list cut off part way is only usable
      # when there is another way to reach the rest of it.
      #
      # Two of the three levels are small and fixed, so the whole of them goes:
      # 240 countries, and at most 377 states or provinces inside one of them,
      # which is Serbia. The level below that is not — England has 4,155 places
      # in it — so it is capped and the panel says to type instead.
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

      def self.call(**options)
        new(**options).call
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
        return Place.children_of(@parent.code).order(:depth, :label, :code) if @parent

        roots
      end

      def roots
        scope = Place.roots.order(:label, :code)
        scope = scope.where(country_code: @countries) if @countries.present?
        scope
      end

      # The first word is a prefix against the place's own name, which is the
      # index this table has. Anything after it is a prefix against a part of
      # the path further up, so "spring il" is Springfield in Illinois and not
      # Spring Hill in Florida, which is what matching anywhere in the string
      # would have made of the l in Hill.
      #
      # Shortest first inside a level, so "unite" answers United States before
      # United Arab Emirates and "chic" answers Chicago before Chic's Beach.
      # Alphabetical is the right order for a list somebody is reading and the
      # wrong one for a list somebody is searching.
      def matches
        words = @term.downcase.split(/\s+/)
        scope = within.where("lower(#{Place.quoted_table_name}.label) like ?", "#{escape(words.first)}%")

        words.drop(1).each do |word|
          scope = scope.where("lower(#{Place.quoted_table_name}.name) like ?", "%,#{escape(word)}%")
        end

        scope.order(:depth, Arel.sql("length(#{Place.quoted_table_name}.label)"), :label, :code)
      end

      def within
        return Place.all if @parent.nil?

        Place.in_country(@parent.country_code)
          .where("#{Place.quoted_table_name}.name like ?", "%#{escape(Place::SEPARATOR + @parent.name)}")
          .where(Place.arel_table[:depth].gt(@parent.depth))
      end

      def escape(value)
        value.gsub(/[\\%_]/) { |char| "\\#{char}" }
      end
    end
  end
end
