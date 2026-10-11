module AhoyDashboard
  # What the picker can offer, and where each list comes from.
  #
  # The picker is one dialog in two steps: the facets, then one facet's options.
  # A facet is a question the data can answer with a list of strings — a
  # dimension's values, the event names already arriving, the property keys the
  # events carry. Which facets are on offer depends on the field that opened it,
  # which is the scope.
  #
  # Same shape as every other registry here: a frozen ALL, a find that raises,
  # and nothing in the database. A dimension facet carries no list of its own; it
  # names a Dimension and the options come off that, so a dimension added to the
  # filter dialog shows up here without being written down twice.
  class PickerFacet
    include ActiveModel::Model

    # Which fields ask for which facets. A scope is named by the form field that
    # opened the picker rather than by the model, because two fields on one form
    # want different lists.
    FILTER = "filter".freeze
    GOAL = "goal".freeze
    SCOPES = [ FILTER, GOAL ].freeze

    # Not a dimension. These two read their own queries, because neither is
    # something the dashboard can be filtered by: an event's name is what a goal
    # is defined as, and a property key is the name of a column that may hold
    # anything.
    EVENTS = "events".freeze
    PROPERTY_KEYS = "property_keys".freeze

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

    def icon
      return AhoyDashboard::PickerFacet::GROUP_ICONS.fetch(group, :layers) unless dimension?

      dimension.group
    end

    class << self
      # Every filterable dimension is a facet, plus the two that are not
      # dimensions at all. Built rather than listed, so the picker cannot fall
      # behind the filter dialog.
      def all
        (dimension_facets + extra_facets).freeze
      end
      alias_method :ALL, :all

      def for_scope(scope)
        wanted = SCOPES.include?(scope.to_s) ? scope.to_s : FILTER

        all.select { |facet| facet.scopes.include?(wanted) }
      end

      # Grouped for the dialog, in the order Dimension declares its groups so the
      # picker reads the same way the filter dialog does.
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

      def dimension_facets
        AhoyDashboard::Dimension.filterable.map do |dimension|
          new(key: dimension.key, label: dimension.filter_label, group: dimension.group,
              scopes: scopes_for(dimension), dimension_key: dimension.key)
        end
      end

      # A page path is what a pageview goal matches on, so the page dimensions
      # answer the goal form too. Nothing else on a goal is a dimension.
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

    GROUP_ICONS = { "Goals" => :target }.freeze
  end
end
