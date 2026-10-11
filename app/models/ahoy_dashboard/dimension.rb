module AhoyDashboard
  # One registry that both the filter dialog and the breakdown cards read, so a
  # dimension's SQL is written once and a filter on it can never disagree with
  # the column it filters.
  class Dimension
    include ActiveModel::Model

    PROPERTY_PREFIX = "prop:".freeze
    PROPERTY_NAME_LENGTH = 255
    PROPERTY_NAME = /\A(?=[^[:cntrl:]]*\S)[^[:cntrl:]]{1,#{PROPERTY_NAME_LENGTH}}\z/
    UNKNOWN_LABEL = "(not set)".freeze
    GOAL_KEY = "goal".freeze
    GROUPS = [ "Page", "Source", "Location", "Device", "Behaviour" ].freeze

    # A goal dimension whose goals have all been deleted has to be valid SQL
    # that groups to nothing, rather than an empty string that would splice into
    # a broken query.
    NOTHING = "null::text".freeze

    attr_reader :key, :label, :group, :scope, :filter_label, :unknown_label, :exclude

    # sql may be a callable, for a dimension whose expression is built out of
    # rows rather than written down. The goal dimension is the reason: it is a
    # case expression over AhoyDashboard::Goal, so it changes the moment somebody
    # adds a goal and cannot be frozen into the registry at boot.
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

    # Most dimensions are both: a way to group and a way to narrow. A few are
    # only a way to group, and page_group is the one that exists today. Its
    # values are the page dimension's values folded, so offering it in the filter
    # menu would put the same paths on the list twice under two names.
    def filterable?
      @filterable
    end

    # Memoized per instance, not per class. The goal dimension is rebuilt by
    # .find on every lookup precisely so this memo cannot outlive a change to
    # the goals table.
    # A callable source is rebuilt every time it is asked for, and only a fixed
    # one is memoized. The whole reason a dimension takes a callable is that its
    # SQL is built out of rows somebody edits — the goals, the page group rules —
    # so caching the first answer for the life of the process would pin the case
    # expression to whatever those rows said when the dashboard was first read,
    # and a rule written afterwards would do nothing until a restart.
    def sql
      return Arel.sql(@sql_source.call.to_s) if @sql_source.respond_to?(:call)

      @sql ||= Arel.sql(@sql_source.to_s)
    end

    ALL = [
      new(key: "page", label: "Page", group: "Page", scope: :event, sql: Sql::EVENT_PATH, events: :page_views),
      # The same paths with the operator's own rules applied. Callable, like the
      # goal dimension, because the rules are rows somebody edits and the case
      # has to be built when the card is read rather than when the class loads.
      # With no rules it is the plain path, so switching grouping on before
      # writing one shows exactly what was there.
      new(key: "page_group", label: "Page group", group: "Page", scope: :event, filterable: false,
          events: :page_views,
          sql: -> { AhoyDashboard::PageGroup.match_case_sql(Sql::EVENT_PATH) || Sql::EVENT_PATH }),
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

      new(key: GOAL_KEY, label: "Goal", group: "Behaviour", scope: :event,
          sql: -> { AhoyDashboard::Sql::GoalCompiler.match_case || NOTHING }),
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

      # Lets a host app declare a dimension this file has never heard of,
      # without editing it, the same way Portal::Tool.register lets a tool
      # add itself from an initializer. Call from
      # `Rails.application.config.to_prepare`, same as every other registry
      # in the app, so it survives a class reload in development.
      #
      # Re-registering the same key overwrites the old entry rather than
      # raising, because to_prepare re-runs the call on every reload.
      # Colliding with a built-in key does raise: Dimension#== hashes on key
      # alone, so a registered dimension with the same key as a built-in one
      # would silently alias it everywhere dimensions are compared or used
      # as hash keys.
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

      # The allowlisted custom properties and any host-registered dimensions
      # are filterable alongside the built-in ones, so the filter dialog offers
      # them by name instead of making somebody hand-write prop:whatever into
      # the URL.
      def filterable
        declared = (ALL + registry.values).select(&:filterable?)
        return declared unless AhoyDashboard::Installation.table?(AhoyDashboard::Property.table_name)

        declared + AhoyDashboard::Property.surfaced.reject { |property| collision(property.key) }.map(&:dimension)
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

      # Rebuilt on every lookup rather than read out of INDEX, because its SQL
      # is a case expression over the goals table and the registry entry was
      # frozen at boot. One lookup memoizes one query; the request-level query
      # cache absorbs the repeats.
      def goal(goals: nil)
        new(key: GOAL_KEY, label: "Goal", group: "Behaviour", scope: :event,
            sql: -> { (goals ? AhoyDashboard::Sql::GoalCompiler.match_case(goals: goals) : AhoyDashboard::Sql::GoalCompiler.match_case) || NOTHING })
      end

      def find_by_key(key)
        find(key)
      rescue ActiveRecord::RecordNotFound
        nil
      end

      # A custom property is named by whoever fired the event, so the name is a
      # parameter and is never allowed near the SQL string unquoted.
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

    # The values on one page of a breakdown, turned into what they mean. Empty
    # unless a host app registered a lookup for this dimension, and only ever a
    # display label: the raw value is still what a filter is built from.
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
