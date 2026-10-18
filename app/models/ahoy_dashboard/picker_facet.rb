module AhoyDashboard
  class PickerFacet
    include ActiveModel::Model

    FILTER = "filter".freeze
    GOAL = "goal".freeze
    SCOPES = [ FILTER, GOAL ].freeze

    EVENTS = "events".freeze
    PROPERTY_KEYS = "property_keys".freeze

    Listing = Data.define(:dimensions, :facets)

    attr_reader :key, :label, :group, :scopes, :dimension_key, :source, :hint

    def initialize(key:, label:, group:, scopes:, dimension_key: nil, source: nil, hint: nil)
      @key = key
      @label = label
      @group = group
      @scopes = Array(scopes).freeze
      @dimension_key = dimension_key
      @source = source
      @hint = hint
    end

    def to_param
      key
    end

    def dimension?
      dimension_key.present?
    end

    def dimension
      dimension? ? AhoyDashboard::Dimension.find(dimension_key) : nil
    end

    class << self
      def all
        dimensions = AhoyDashboard::Dimension.filterable
        listing = AhoyDashboard::Current.picker_facets
        return listing.facets if listing && listing.dimensions.equal?(dimensions)

        facets = (dimension_facets(dimensions) + extra_facets).freeze
        AhoyDashboard::Current.picker_facets = Listing.new(dimensions: dimensions, facets: facets)
        facets
      end
      alias_method :ALL, :all

      def for_scope(scope)
        wanted = SCOPES.include?(scope.to_s) ? scope.to_s : FILTER

        all.select { |facet| facet.scopes.include?(wanted) }
      end

      def grouped(scope)
        for_scope(scope).group_by(&:group).sort_by { |group, _| group_order.index(group) || group_order.size }
      end

      def find(key)
        all.find { |facet| facet.key == key.to_s } ||
          raise(ActiveRecord::RecordNotFound, "no picker facet #{key}")
      end

      def find_by_key(key)
        return if key.blank?

        all.find { |facet| facet.key == key.to_s }
      end

      private

      def group_order
        @group_order ||= AhoyDashboard::Dimension::GROUPS + [ "Goals" ]
      end

      def dimension_facets(dimensions)
        dimensions.map do |dimension|
          new(key: dimension.key, label: dimension.filter_label, group: dimension.group,
              scopes: scopes_for(dimension), dimension_key: dimension.key)
        end
      end

      def scopes_for(dimension)
        dimension.group == "Page" ? [ FILTER, GOAL ] : [ FILTER ]
      end

      def extra_facets
        [
          new(key: EVENTS, label: "Events", group: "Goals", scopes: [ GOAL ], source: EVENTS,
              hint: "Names your app already sends"),
          new(key: PROPERTY_KEYS, label: "Property keys", group: "Goals", scopes: [ GOAL ],
              source: PROPERTY_KEYS, hint: "Keys the recent events carry")
        ]
      end
    end
  end
end
