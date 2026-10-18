module AhoyDashboard
  module Assistant
    class Slice
      KEY = "slice".freeze
      NONE = AhoyDashboard::QueryForm::NO_FILTERS

      class InvalidFilters < StandardError
        attr_reader :problems

        def initialize(problems)
          @problems = problems
          super(problems.join("; "))
        end
      end

      attr_reader :source, :dropped

      def self.snapshot(query)
        {
          "filters" => query.filters.any? ? query.filters.to_param : NONE,
          "crawlers" => query.include_crawlers?,
          "internal" => query.include_internal?
        }
      end

      def self.from_context(context)
        stored = context.is_a?(Hash) ? context[KEY] : nil
        return new if !stored.is_a?(Hash) || !stored.key?("filters")

        entries = stored["filters"] == NONE ? [] : Array(stored["filters"])
        kept, dropped = entries.partition { |entry| problem(entry).nil? }

        new(filters: kept, crawlers: stored["crawlers"], internal: stored["internal"],
            source: :conversation, dropped: dropped.map { |entry| describe(entry) })
      end

      def self.problem(raw)
        entry = AhoyDashboard::FilterEntry.read(raw)
        return "#{raw.inspect} is not a filter" if entry.nil?

        key = entry.field(:dimension)
        operator = entry.field(:operator).presence
        value = entry.field(:value)
        dimension = entry.dimension

        return "no dimension called #{key.inspect}" if dimension.nil?
        return "#{dimension.key} is kept out of the assistant by the site's owner" if AhoyDashboard::Assistant.withheld?(dimension.key)
        return "#{dimension.key} cannot be filtered on" unless dimension.filterable?
        return "no operator called #{operator.inspect}" if operator && !AhoyDashboard::Filter::OPERATORS.key?(operator.to_s)
        return "#{dimension.key} has no value" if value.to_s.blank?

        "group #{entry.raw_group.inspect} is not a whole number from 0 up" unless entry.group_ok?
      end

      def self.describe(raw)
        entry = AhoyDashboard::FilterEntry.read(raw)
        return raw.inspect if entry.nil?

        key = entry.dimension_key
        return "a filter on #{key}, kept out of the assistant by the site's owner" if AhoyDashboard::Assistant.withheld?(key)

        [ entry.field(:dimension), entry.field(:operator) || AhoyDashboard::Filter::DEFAULT_OPERATOR,
          entry.field(:value) ].join(" ")
      end

      private_class_method :describe

      def initialize(filters: nil, crawlers: false, internal: false, source: :default, dropped: [])
        @filters = filters
        @crawlers = crawlers.present?
        @internal = internal.present?
        @source = source
        @dropped = dropped
      end

      def with(asked)
        return self if asked.nil?

        entries = Array(asked)
        problems = entries.map { |entry| self.class.problem(entry) }.select { |value| value }
        raise InvalidFilters, problems if problems.any?

        self.class.new(filters: entries.map { |entry| normalize(AhoyDashboard::FilterEntry.read(entry)) }, crawlers: crawlers?,
                       internal: internal?, source: :asked)
      end

      def crawlers?
        @crawlers
      end

      def internal?
        @internal
      end

      def default?
        @filters.nil?
      end

      def form_params
        {
          filters: (default? ? nil : @filters.presence || NONE),
          crawlers: (AhoyDashboard::QueryForm::CRAWLERS_ON if crawlers?),
          internal: (AhoyDashboard::QueryForm::INTERNAL_ON if internal?)
        }.compact
      end

      def from_label
        case source
        when :conversation then "the screen the question was asked from"
        when :asked then "you"
        else "the dashboard's defaults"
        end
      end

      private

      def normalize(entry)
        {
          "dimension" => entry.dimension_key,
          "operator" => entry.operator || AhoyDashboard::Filter::DEFAULT_OPERATOR,
          "value" => entry.value,
          "group" => entry.group
        }.compact
      end
    end
  end
end
