module AhoyDashboard
  # One facet's options, whatever kind of facet it is.
  #
  # A dimension facet is a group by on that dimension, so the rows come back with
  # the visitors behind them and the picker can print a count. The two facets
  # that are not dimensions have no visitor to count — an event name is a name
  # and a property key is a column — so those come back with no number rather
  # than with a zero, and the view prints nothing where the count would go.
  class PickerOptionsQuery
    LIMIT = 40
    MAX_LIMIT = 200

    Option = Data.define(:label, :visitors) do
      def counted?
        !visitors.nil?
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(scope:, facet:, term: nil, limit: LIMIT)
      @scope = scope
      @facet = facet
      @term = term.to_s.strip
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
    end

    def call
      return dimension_options if facet.dimension?

      matching(bare_options).map { |label| Option.new(label: label, visitors: nil) }
    end

    private

    attr_reader :scope, :facet, :term, :limit

    def dimension_options
      AhoyDashboard::FilterOptionsQuery.call(
        scope: scope,
        dimension: facet.dimension,
        query: term.presence,
        limit: limit,
        counted: true
      ).map { |label, visitors| Option.new(label: label, visitors: visitors) }
    end

    # Both of these are cached lists rather than a query the term can reach into,
    # so the narrowing happens here. They are short — a hundred names at the
    # outside — and running the group by again per keystroke to push a LIKE into
    # it would cost more than filtering the answer.
    def bare_options
      case facet.source
      when AhoyDashboard::PickerFacet::EVENTS then AhoyDashboard::EventNamesQuery.call(scope: scope)
      when AhoyDashboard::PickerFacet::PROPERTY_KEYS then AhoyDashboard::PropertyKeysQuery.call(scope: scope)
      else []
      end
    end

    def matching(labels)
      found = term.present? ? labels.select { |label| label.to_s.downcase.include?(term.downcase) } : labels

      found.first(limit)
    end
  end
end
