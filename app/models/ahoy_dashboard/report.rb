module AhoyDashboard
  # The cards under the chart. A card is a title and a set of tabs, and a tab is
  # a dimension plus the columns to show for it, so the reports controller is one
  # controller rather than five.
  class Report
    include ActiveModel::Model

    # The same rows counted a different way: one tab, one question, and a choice
    # of which dimension the grouping runs on. Which options a tab offers is
    # decided by what its own data can answer, which is why the entry pages tab
    # can offer a full URL and the top pages tab cannot: a page view records
    # request.path and no host, and the landing page is a whole URL.
    #
    # The first option is the one the tab opens on, so its dimension_key has to
    # be the tab's own. label_column and detail_metrics are per option because
    # neither the heading nor the columns survive a change of grouping: a
    # controller cannot be asked how far down its pages were read.
    Breakdown = Data.define(:key, :label, :dimension_key, :label_column, :detail_metrics) do
      def initialize(detail_metrics: nil, **rest)
        super(detail_metrics: detail_metrics, **rest)
      end

      def to_param
        key
      end
    end

    # dimension_key may be a callable, for a tab that points at whichever
    # dimension the operator configured rather than one written down here. The
    # properties tab is the reason: which custom property it opens on depends on
    # AhoyDashboard::Property, which is rows, not code. Read it through
    # #resolved_dimension_key, never off the member directly.
    Tab = Data.define(:key, :label, :dimension_key, :metrics, :detail_metrics, :label_column,
                      :breakdowns) do
      def initialize(breakdowns: [], **rest)
        super(breakdowns: breakdowns.freeze, **rest)
      end

      def resolved_dimension_key
        dimension_key.respond_to?(:call) ? dimension_key.call.to_s : dimension_key.to_s
      end

      def dimension
        Dimension.find(resolved_dimension_key)
      end

      def property_tab?
        resolved_dimension_key.start_with?(Dimension::PROPERTY_PREFIX)
      end

      def goal_tab?
        resolved_dimension_key == Dimension::GOAL_KEY
      end

      def breakdown_options
        Array(breakdowns)
      end

      # Same shape as Report#tab: a key nobody registered is somebody editing the
      # URL, and the answer is the option the card opens on rather than a 500.
      # nil when the tab offers no choice at all.
      def breakdown(wanted = nil)
        return if breakdown_options.empty?

        breakdown_options.find { |candidate| candidate.key == wanted.to_s } || breakdown_options.first
      end

      # Which option the card is actually grouping by, read back off the dimension
      # rather than off the param it arrived as. #resolve folds an option's values
      # into the tab and keeps no record of which one it was, and deriving it from
      # the dimension is the only reading that cannot disagree with the rows on
      # screen: a hand-edited or foreign value ticks the option the card fell back
      # to instead of one it is not showing. The picker and every link built off
      # the card read this, so they cannot drift apart.
      def active_breakdown
        return if breakdown_options.empty?

        breakdown_options.find { |option| option.dimension_key == resolved_dimension_key } ||
          breakdown_options.first
      end

      # A card's own dimension overrides folded back into the tab, so everything
      # downstream reads one object rather than resolving the grouping a second
      # way of its own. That is what keeps the heading, the columns, the details
      # modal and the CSV export agreeing with the card in front of somebody.
      def resolve(breakdown: nil, property: nil)
        for_breakdown(breakdown).for_property(property)
      end

      def for_breakdown(wanted)
        chosen = breakdown(wanted)
        return self if chosen.nil?

        with(
          dimension_key: chosen.dimension_key,
          label_column: chosen.label_column,
          detail_metrics: chosen.detail_metrics || detail_metrics
        )
      end

      # A property name is a raw query string parameter, so it goes through the
      # registry rather than into the tab: a name that is not a property name
      # leaves the card on the key the allowlist opens it with.
      def for_property(name)
        return self unless property_tab? && name.is_a?(String) && name.present?

        key = "#{Dimension::PROPERTY_PREFIX}#{name}"

        Dimension.find_by_key(key) ? with(dimension_key: key) : self
      end

      def to_param
        key
      end
    end

    # Clicking a row filters the whole dashboard, and these cards answer a
    # narrower question once it is filtered: a country is only interesting for
    # its regions. Deepest step first, so a region filter beats a country one.
    DRILLDOWNS = {
      "locations" => [ [ "region", "cities" ], [ "country", "regions" ] ],
      "sources" => [ [ "source", "referrers" ], [ "channel", "sources" ] ]
    }.freeze

    CARD_ORDER = %w[sources pages locations devices behaviours].freeze

    # The dashboard pulls this one out of the grid loop and renders it after the
    # funnels, so goals and properties read last: a conversion only means something
    # once you know where people came from and what they looked at. It stays in
    # CARD_ORDER because the export menu iterates the whole set.
    BEHAVIOURS = "behaviours".freeze

    CARD_METRICS = %w[visitors].freeze
    SESSION_METRICS = %w[visitors visits bounce_rate visit_duration].freeze

    attr_reader :key, :title, :tabs, :default_tab_key

    def initialize(key:, title:, tabs:, default_tab:, wide: false)
      @key = key
      @title = title
      @tabs = tabs.freeze
      @default_tab_key = default_tab
      @wide = wide
    end

    ALL = [
      new(key: "sources", title: "Top sources", default_tab: "channels", wide: true, tabs: [
        Tab.new(key: "channels", label: "Channels", dimension_key: "channel",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Channel"),
        Tab.new(key: "sources", label: "Sources", dimension_key: "source",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Source"),
        Tab.new(key: "utm_medium", label: "UTM medium", dimension_key: "utm_medium",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "UTM medium"),
        Tab.new(key: "utm_source", label: "UTM source", dimension_key: "utm_source",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "UTM source"),
        Tab.new(key: "utm_campaign", label: "UTM campaign", dimension_key: "utm_campaign",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "UTM campaign"),
        Tab.new(key: "utm_term", label: "UTM term", dimension_key: "utm_term",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "UTM term"),
        Tab.new(key: "utm_content", label: "UTM content", dimension_key: "utm_content",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "UTM content"),
        Tab.new(key: "referrers", label: "Referrers", dimension_key: "referrer",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Referrer")
      ]),

      # Scroll depth and time on page are on the top pages tab only. The exit page
      # dimension reads a column off a join that carries no events, so it can only
      # answer them with a blank, and the entry page is a property of the session
      # rather than of the reading.
      new(key: "pages", title: "Top pages", default_tab: "pages", wide: true, tabs: [
        Tab.new(key: "pages", label: "Top pages", dimension_key: "page",
                metrics: CARD_METRICS,
                detail_metrics: %w[visitors pageviews bounce_rate scroll_depth engagement_time],
                label_column: "Page url",
                breakdowns: [
                  Breakdown.new(key: "path", label: "Path", dimension_key: "page",
                                label_column: "Page url"),
                  # The same paths with the operator's page group rules applied.
                  # A breakdown rather than a toggle of its own, because that is
                  # what it is: another reading of this card's own dimension,
                  # beside the two already here.
                  Breakdown.new(key: "grouped", label: "Grouped", dimension_key: "page_group",
                                label_column: "Page group"),
                  # The engagement event carries a path and nothing else, so how
                  # far down a controller's pages were read is a question it
                  # cannot answer and the columns come off rather than read zero.
                  Breakdown.new(key: "controller", label: "Rails controller",
                                dimension_key: "controller", label_column: "Rails controller",
                                detail_metrics: %w[visitors pageviews bounce_rate])
                ]),
        Tab.new(key: "entry_pages", label: "Entry pages", dimension_key: "entry_page",
                metrics: CARD_METRICS, detail_metrics: %w[visitors visits visit_duration],
                label_column: "Page url",
                breakdowns: [
                  Breakdown.new(key: "path", label: "Path", dimension_key: "entry_page",
                                label_column: "Page url"),
                  Breakdown.new(key: "url", label: "URL", dimension_key: "entry_url",
                                label_column: "Full url"),
                  Breakdown.new(key: "host", label: "Hostname", dimension_key: "entry_host",
                                label_column: "Hostname")
                ]),
        Tab.new(key: "exit_pages", label: "Exit pages", dimension_key: "exit_page",
                metrics: CARD_METRICS, detail_metrics: %w[visitors pageviews],
                label_column: "Page url")
      ]),

      new(key: "locations", title: "Locations", default_tab: "countries", tabs: [
        Tab.new(key: "countries", label: "Countries", dimension_key: "country",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Country"),
        Tab.new(key: "regions", label: "Regions", dimension_key: "region",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Region"),
        Tab.new(key: "cities", label: "Cities", dimension_key: "city",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "City")
      ]),

      new(key: "devices", title: "Devices", default_tab: "browser", tabs: [
        Tab.new(key: "browser", label: "Browser", dimension_key: "browser",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Browser"),
        Tab.new(key: "os", label: "OS", dimension_key: "os",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "OS"),
        Tab.new(key: "size", label: "Size", dimension_key: "device",
                metrics: CARD_METRICS, detail_metrics: SESSION_METRICS, label_column: "Size")
      ]),

      new(key: "behaviours", title: "Behaviours", default_tab: "goals", tabs: [
        Tab.new(key: "goals", label: "Goal conversions", dimension_key: "goal",
                metrics: %w[visitors conversion_rate],
                detail_metrics: %w[visitors events conversion_rate revenue_total revenue_average],
                label_column: "Goal"),
        Tab.new(key: "properties", label: "Custom properties",
                dimension_key: -> { AhoyDashboard::Property.default_dimension_key },
                metrics: CARD_METRICS, detail_metrics: %w[visitors pageviews],
                label_column: "Property")
      ])
    ].freeze

    INDEX = ALL.index_by(&:key).freeze

    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    RESERVED_KEYS = %w[search_console facet].freeze
    RESERVED_PREFIXES = %w[funnel_].freeze

    class << self
      def all
        ALL + registry.values
      end

      def card_order
        CARD_ORDER
      end

      def cards
        CARD_ORDER.map { |key| INDEX.fetch(key) } + registry.values
      end

      def find(key)
        key = key.to_s

        INDEX[key] || registry[key] ||
          raise(ActiveRecord::RecordNotFound, "no dashboard report #{key}")
      end

      def find_by_key(key)
        key = key.to_s

        INDEX[key] || registry[key]
      end

      def registry
        @registry ||= {}
      end

      def register(key:, title:, tabs:, default_tab: nil, wide: false)
        key = key.to_s
        tabs = Array(tabs).freeze

        validate_key!(key)
        validate_tabs!(key, tabs)

        registry[key] = new(key: key, title: title, tabs: tabs, wide: wide,
                            default_tab: (default_tab || tabs.first.key).to_s)
      end

      private

      def validate_key!(key)
        unless key.match?(KEY_FORMAT)
          raise ArgumentError, "dashboard report key #{key.inspect} must match #{KEY_FORMAT.inspect}"
        end

        raise ArgumentError, "dashboard report #{key.inspect} is already built in" if INDEX.key?(key)

        if key.in?(RESERVED_KEYS) || RESERVED_PREFIXES.any? { |prefix| key.start_with?(prefix) }
          raise ArgumentError, "dashboard report key #{key.inspect} is reserved"
        end
      end

      def validate_tabs!(key, tabs)
        raise ArgumentError, "dashboard report #{key.inspect} registers no tabs" if tabs.empty?

        tab_keys = tabs.map { |tab| tab.key.to_s }
        unless tab_keys == tab_keys.uniq
          raise ArgumentError, "dashboard report #{key.inspect} registers a tab key twice"
        end

        tabs.each { |tab| validate_tab!("#{key}/#{tab.key}", tab) }
      end

      def validate_tab!(label, tab)
        raise ArgumentError, "dashboard tab #{label} has no label" if tab.label.blank?
        raise ArgumentError, "dashboard tab #{label} has no label column" if tab.label_column.blank?

        validate_metrics!(label, Array(tab.metrics) + Array(tab.detail_metrics))
        validate_dimension!(label, tab.dimension_key)

        tab.breakdown_options.each do |option|
          validate_metrics!("#{label}/#{option.key}", Array(option.detail_metrics))
          validate_dimension!("#{label}/#{option.key}", option.dimension_key)
        end
      end

      def validate_metrics!(label, metrics)
        metrics.each do |metric|
          AhoyDashboard::Metric.find(metric)
        rescue ActiveRecord::RecordNotFound
          raise ArgumentError, "dashboard tab #{label} asks for the metric #{metric.inspect}"
        end
      end

      def validate_dimension!(label, dimension_key)
        return if dimension_key.respond_to?(:call)

        AhoyDashboard::Dimension.find(dimension_key)
      rescue ActiveRecord::RecordNotFound
        raise ArgumentError, "dashboard tab #{label} points at #{dimension_key.inspect}, which is not a dimension"
      rescue ActiveRecord::ActiveRecordError
        nil
      end
    end

    def to_param
      key
    end

    def drilldown_tab(filters)
      steps = DRILLDOWNS[key]
      return if steps.nil?

      applied = filters.pinned.map { |filter| filter.dimension.key }
      steps.find { |dimension_key, _tab_key| applied.include?(dimension_key) }&.last
    end

    def default_tab
      tabs.find { |candidate| candidate.key == default_tab_key } || tabs.first
    end

    def tab(wanted = nil)
      wanted = wanted.respond_to?(:key) ? wanted.key : wanted.to_s

      tabs.find { |candidate| candidate.key == wanted } || default_tab
    end

    def wide?
      @wide
    end
  end
end
