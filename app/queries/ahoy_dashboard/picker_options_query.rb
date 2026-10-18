module AhoyDashboard
  class PickerOptionsQuery < AhoyDashboard::Query
    LIMIT = 40
    MAX_LIMIT = 200

    Option = Data.define(:label, :visitors) do
      def counted?
        !visitors.nil?
      end
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
