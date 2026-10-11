module AhoyDashboard
  # The dialogs a filter chip reopens to. A category is a named group of related
  # dimensions, which is coarser than Dimension::GROUPS: Source is one dialog
  # with three rows, because source, channel and referrer are the same question
  # asked three ways and somebody who wants one of them wants the other two in
  # reach.
  #
  # Every filterable dimension belongs to exactly one category. A dimension that
  # is in none of them cannot be filtered from the UI at all, which is what
  # spec/models/ahoy_dashboard/filter_category_spec.rb pins.
  class FilterCategory
    include ActiveModel::Model

    HEADINGS = [ "URL", "Acquisition", "Device", "Behaviour" ].freeze
    DEFAULT_KEY = "page".freeze
    PROPERTY_KEY = "property".freeze

    attr_reader :key, :label, :heading

    # dimensions may be a callable, for a category whose rows are rows in a table
    # rather than a written list. The custom properties are the reason: the
    # allowlist changes the moment somebody edits it in settings and cannot be
    # frozen into the registry at boot.
    def initialize(key:, label:, heading:, dimensions:)
      @key = key
      @label = label
      @heading = heading
      @dimension_source = dimensions
    end

    def dimension_keys
      @dimension_source.respond_to?(:call) ? Array(@dimension_source.call) : @dimension_source
    end

    def dimensions
      dimension_keys.map { |dimension_key| AhoyDashboard::Dimension.find_by_key(dimension_key) }.select { |value| value }
    end

    ALL = [
      new(key: DEFAULT_KEY, label: "Page", heading: "URL",
          dimensions: %w[page entry_page exit_page format controller]),
      new(key: "hostname", label: "Hostname", heading: "URL",
          dimensions: %w[entry_host entry_url]),

      new(key: "source", label: "Source", heading: "Acquisition",
          dimensions: %w[source channel referrer]),
      new(key: "utm", label: "UTM tags", heading: "Acquisition",
          dimensions: %w[utm_source utm_medium utm_campaign utm_term utm_content]),

      new(key: "location", label: "Location", heading: "Device",
          dimensions: %w[country region city]),
      new(key: "screen_size", label: "Screen size", heading: "Device", dimensions: %w[device]),
      new(key: "browser", label: "Browser", heading: "Device", dimensions: %w[browser]),
      new(key: "os", label: "Operating system", heading: "Device", dimensions: %w[os os_version]),

      new(key: "goal", label: "Goal", heading: "Behaviour", dimensions: %w[goal]),
      new(key: PROPERTY_KEY, label: "Property", heading: "Behaviour",
          dimensions: -> { AhoyDashboard::Dimension.filterable.select(&:property?).map(&:key) }),
      new(key: "crawler", label: "Crawler", heading: "Behaviour", dimensions: %w[crawler]),
      new(key: "browsed", label: "Viewed a page", heading: "Behaviour", dimensions: %w[browsed]),

      # Empty until a host app calls AhoyDashboard::Dimension.register. Surfaced
      # the same way the properties category is: a category with nothing in
      # it just doesn't show up in the menu, per .surfaced below.
      new(key: "custom", label: "Custom", heading: "Behaviour",
          dimensions: -> { AhoyDashboard::Dimension.registry.keys })
    ].freeze

    INDEX = ALL.index_by(&:key).freeze

    class << self
      def all
        ALL
      end

      # A category with nothing in it is a menu item that opens an empty form.
      # The properties category is the one this happens to: it holds whatever the
      # allowlist holds, which on a fresh install is nothing.
      def surfaced
        ALL.select { |category| category.dimension_keys.any? }
      end

      def grouped
        offered = surfaced

        HEADINGS.map do |heading|
          categories = offered.select { |category| category.heading == heading }

          [ heading, categories ] if categories.any?
        end.select { |value| value }
      end

      def find(key)
        INDEX.fetch(key.to_s) { raise ActiveRecord::RecordNotFound, "no dashboard filter category #{key}" }
      end

      def find_by_key(key)
        INDEX[key.to_s]
      end

      # Which category a dimension belongs to, so a filter already on the bar can
      # be opened back up in the form that made it.
      def for_dimension(dimension_key)
        wanted = dimension_key.to_s

        ALL.find { |category| category.dimension_keys.include?(wanted) }
      end

      def for_filters(filters)
        filters.map { |filter| for_dimension(filter.dimension.key) }.compact.uniq
      end

      def default
        INDEX.fetch(DEFAULT_KEY)
      end
    end

    def to_param
      key
    end

    def title
      "Filter by #{label}"
    end

    def ==(other)
      other.is_a?(FilterCategory) && other.key == key
    end
    alias_method :eql?, :==

    def hash
      key.hash
    end
  end
end
