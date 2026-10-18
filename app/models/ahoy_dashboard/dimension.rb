module AhoyDashboard
  class Dimension
    include ActiveModel::Model

    PROPERTY_PREFIX = "prop:".freeze
    PROPERTY_NAME_LENGTH = 255
    PROPERTY_NAME = /\A(?=[^[:cntrl:]]*\S)[^[:cntrl:]]{1,#{PROPERTY_NAME_LENGTH}}\z/
    UNKNOWN_LABEL = "(not set)".freeze
    GOAL_KEY = "goal".freeze
    GROUPS = [ "Page", "Source", "Location", "Device", "Behaviour" ].freeze

    NOTHING = "null::text".freeze
    GOAL_SQL = -> { AhoyDashboard::Sql::GoalCompiler.match_case || NOTHING }
    PAGE_GROUP_SQL = -> { AhoyDashboard::PageGroup.match_case_sql(Sql::EVENT_PATH) || Sql::EVENT_PATH }
    REQUEST_SQL = [ GOAL_SQL, PAGE_GROUP_SQL ].freeze

    Listing = Data.define(:registered, :dimensions)

    attr_reader :key, :label, :group, :scope, :filter_label, :unknown_label, :exclude

    def initialize(key:, label:, group:, scope:, sql:, filter_label: nil,
                   unknown_label: UNKNOWN_LABEL, filterable: true, exclude: nil, events: :any)
      @key = key
      @label = label
      @group = group
      @scope = scope.to_sym
      @sql_source = sql
      @filter_label = filter_label || label
      @unknown_label = unknown_label
      @filterable = filterable
      @exclude = exclude
      @events = events.to_sym
    end

    def page_views_only?
      @events == :page_views
    end

    def filterable?
      @filterable
    end

    def sql
      return @sql ||= Arel.sql(@sql_source.to_s) unless @sql_source.respond_to?(:call)
      return Arel.sql(@sql_source.call.to_s) unless REQUEST_SQL.include?(@sql_source)

      built = (AhoyDashboard::Current.dimension_sql ||= {})
      built[@sql_source] ||= Arel.sql(@sql_source.call.to_s)
    end

    def exits?
      sql.to_s.include?(ExitPagesQuery::ALIAS)
    end

    ALL = [
      new(key: "page", label: "Page", group: "Page", scope: :event, sql: Sql::EVENT_PATH, events: :page_views),
      new(key: "page_group", label: "Page group", group: "Page", scope: :event, filterable: false,
          events: :page_views, sql: PAGE_GROUP_SQL),
      new(key: "entry_page", label: "Entry page", group: "Page", scope: :visit, sql: Sql::ENTRY_PATH,
          exclude: Sql::NEVER_VIEWED_A_PAGE),
      new(key: "entry_url", label: "Entry URL", group: "Page", scope: :visit, sql: Sql::ENTRY_URL,
          exclude: Sql::NEVER_VIEWED_A_PAGE),
      new(key: "entry_host", label: "Entry hostname", group: "Page", scope: :visit,
          sql: Sql::ENTRY_HOST, exclude: Sql::NEVER_VIEWED_A_PAGE),
      new(key: "exit_page", label: "Exit page", group: "Page", scope: :visit,
          sql: Arel.sql("dash_exits.path")),

      new(key: "channel", label: "Channel", group: "Source", scope: :visit, sql: Sql::CHANNEL),
      new(key: "source", label: "Source", group: "Source", scope: :visit, sql: Sql::SOURCE),
      new(key: "referrer", label: "Referrer URL", group: "Source", scope: :visit,
          sql: Sql::REFERRER, exclude: Sql::INTERNAL_DOMAIN),
      new(key: "utm_medium", label: "UTM medium", group: "Source", scope: :visit,
          sql: Arel.sql("ahoy_visits.utm_medium")),
      new(key: "utm_source", label: "UTM source", group: "Source", scope: :visit,
          sql: Arel.sql("ahoy_visits.utm_source")),
      new(key: "utm_campaign", label: "UTM campaign", group: "Source", scope: :visit,
          sql: Arel.sql("ahoy_visits.utm_campaign")),
      new(key: "utm_term", label: "UTM term", group: "Source", scope: :visit,
          sql: Arel.sql("ahoy_visits.utm_term")),
      new(key: "utm_content", label: "UTM content", group: "Source", scope: :visit,
          sql: Arel.sql("ahoy_visits.utm_content")),

      new(key: "country", label: "Country", group: "Location", scope: :visit,
          sql: Arel.sql("ahoy_visits.country")),
      new(key: "region", label: "Region", group: "Location", scope: :visit,
          sql: Arel.sql("ahoy_visits.region")),
      new(key: "city", label: "City", group: "Location", scope: :visit,
          sql: Arel.sql("ahoy_visits.city")),

      new(key: "browser", label: "Browser", group: "Device", scope: :visit,
          sql: Arel.sql("ahoy_visits.browser")),
      new(key: "os", label: "OS", group: "Device", scope: :visit, sql: Arel.sql("ahoy_visits.os")),
      new(key: "os_version", label: "OS version", group: "Device", scope: :visit,
          sql: Arel.sql("ahoy_visits.os_version")),
      new(key: "device", label: "Device", group: "Device", scope: :visit,
          sql: Arel.sql("ahoy_visits.device_type")),

      new(key: GOAL_KEY, label: "Goal", group: "Behaviour", scope: :event, sql: GOAL_SQL),
      new(key: "format", label: "Page format", group: "Behaviour", scope: :event,
          sql: Arel.sql("ahoy_events.properties ->> 'format'")),
      new(key: "crawler", label: "Crawler", group: "Behaviour", scope: :event,
          sql: Arel.sql("ahoy_events.properties ->> 'crawler'")),
      new(key: "controller", label: "Rails controller", group: "Behaviour", scope: :event,
          sql: Arel.sql("ahoy_events.properties ->> 'controller'")),
      new(key: "browsed", label: "Viewed a page", group: "Behaviour", scope: :visit, sql: Sql::BROWSED)
    ].freeze

    INDEX = ALL.index_by(&:key).freeze

    class << self
      def all
        ALL + registry.values
      end

      def with_properties
        properties = begin
          AhoyDashboard::Property.surfaced.map(&:dimension)
        rescue ActiveRecord::ActiveRecordError
          []
        end

        (all + properties).uniq(&:key)
      end

      def register(key:, label:, group:, scope:, sql:, filter_label: nil, unknown_label: UNKNOWN_LABEL)
        key = key.to_s
        if INDEX.key?(key) || key == GOAL_KEY || key.start_with?(PROPERTY_PREFIX)
          raise ArgumentError, "dashboard dimension #{key.inspect} is already built in"
        end

        registry[key] = new(key: key, label: label, group: group, scope: scope, sql: sql,
                             filter_label: filter_label, unknown_label: unknown_label)
      end

      def registry
        @registry ||= {}
      end

      def filterable
        registered = registry.values.map(&:object_id)
        listing = AhoyDashboard::Current.filterable_dimensions
        return listing.dimensions if listing && listing.registered == registered

        dimensions = declared_filterable.freeze
        AhoyDashboard::Current.filterable_dimensions = Listing.new(registered: registered, dimensions: dimensions)
        dimensions
      end

      def collision(name)
        wanted = normalize_name(name)
        return if wanted.blank?

        (ALL + registry.values).find do |dimension|
          normalize_name(dimension.key) == wanted || normalize_name(dimension.label) == wanted
        end
      end

      def normalize_name(value)
        value.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      def grouped(dimensions = filterable)
        sets = dimensions.uniq.group_by { |dimension| dimension.group.to_s }
        declared = GROUPS & sets.keys

        (declared + (sets.keys - declared)).map { |group| [ group, sets.fetch(group) ] }
      end

      def find(key)
        key = key.to_s
        return property(key.delete_prefix(PROPERTY_PREFIX)) if key.start_with?(PROPERTY_PREFIX)
        return goal if key == GOAL_KEY

        INDEX[key] || registry[key] || raise(ActiveRecord::RecordNotFound, "no dashboard dimension #{key}")
      end

      def goal(goals: nil)
        sql = goals ? -> { AhoyDashboard::Sql::GoalCompiler.match_case(goals: goals) || NOTHING } : GOAL_SQL

        new(key: GOAL_KEY, label: "Goal", group: "Behaviour", scope: :event, sql: sql)
      end

      def find_by_key(key)
        find(key)
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def declared_filterable
        declared = (ALL + registry.values).select(&:filterable?)
        return declared unless AhoyDashboard::Installation.table?(AhoyDashboard::Property.table_name)

        declared + AhoyDashboard::Property.surfaced.reject { |property| collision(property.key) }.map(&:dimension)
      end
      private :declared_filterable

      def property(name)
        name = name.to_s
        raise ActiveRecord::RecordNotFound, "no dashboard property #{name}" unless name.match?(PROPERTY_NAME)

        new(key: "#{PROPERTY_PREFIX}#{name}", label: name, group: "Behaviour", scope: :event,
            sql: Arel.sql("ahoy_events.properties ->> #{ActiveRecord::Base.connection.quote(name)}"))
      end
    end

    def to_param
      key
    end

    def labels_for(values)
      AhoyDashboard::ValueLabels.for(key, values)
    end

    def property?
      key.start_with?(PROPERTY_PREFIX)
    end

    def visit?
      scope == :visit
    end

    def event?
      scope == :event
    end

    def ==(other)
      other.is_a?(Dimension) && other.key == key
    end
    alias_method :eql?, :==

    def hash
      key.hash
    end
  end
end
