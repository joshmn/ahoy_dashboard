module AhoyDashboard
  module Assistant
    class Slice
      KEY = "slice".freeze
      GROUP_LIMIT = 1_000_000
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

      def self.problem(entry)
        return "#{entry.inspect} is not a filter" unless entry.respond_to?(:key?)

        key = entry["dimension"] || entry[:dimension]
        operator = (entry["operator"] || entry[:operator]).presence
        value = entry["value"] || entry[:value]
        group = entry.key?("group") ? entry["group"] : entry[:group]
        dimension = AhoyDashboard::Dimension.find_by_key(key.to_s)

        return "no dimension called #{key.inspect}" if dimension.nil?
        return "#{dimension.key} is kept out of the assistant by the site's owner" if AhoyDashboard::Assistant.withheld?(dimension.key)
        return "#{dimension.key} cannot be filtered on" unless dimension.filterable?
        return "no operator called #{operator.inspect}" if operator && !AhoyDashboard::Filter::OPERATORS.key?(operator.to_s)
        return "#{dimension.key} has no value" if value.to_s.blank?

        "group #{group.inspect} is not a whole number from 0 up" unless group.nil? || group?(group)
      end

      def self.group?(group)
        return group >= 0 && group < GROUP_LIMIT if group.is_a?(Integer)

        group.is_a?(String) && group.match?(/\A\d{1,6}\z/)
      end

      def self.describe(entry)
        return entry.inspect unless entry.respond_to?(:key?)

        key = (entry["dimension"] || entry[:dimension]).to_s
        return "a filter on #{key}, kept out of the assistant by the site's owner" if AhoyDashboard::Assistant.withheld?(key)

        [ entry["dimension"] || entry[:dimension], entry["operator"] || entry[:operator] || AhoyDashboard::Filter::DEFAULT_OPERATOR,
          entry["value"] || entry[:value] ].join(" ")
      end

      private_class_method :describe, :group?

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

        self.class.new(filters: entries.map { |entry| normalize(entry) }, crawlers: crawlers?,
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
        group = entry.key?("group") ? entry["group"] : entry[:group]

        {
          "dimension" => (entry["dimension"] || entry[:dimension]).to_s,
          "operator" => (entry["operator"] || entry[:operator]).presence&.to_s || AhoyDashboard::Filter::DEFAULT_OPERATOR,
          "value" => (entry["value"] || entry[:value]).to_s,
          "group" => (group.to_s.to_i unless group.nil?)
        }.compact
      end
    end
  end
end
