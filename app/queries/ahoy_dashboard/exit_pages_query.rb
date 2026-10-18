module AhoyDashboard
  class ExitPagesQuery < AhoyDashboard::Query
    ALIAS = "dash_exits".freeze

    class << self
      def join_sql(scope)
        "left join (#{call(scope: scope).to_sql}) #{ALIAS} on #{ALIAS}.visit_id = ahoy_visits.id"
      end

      def relation(source)
        AhoyDashboard.visit.unscoped.from(Arel.sql("(#{new(source: source).call.to_sql}) #{ALIAS}"))
      end
    end

    def initialize(scope: nil, source: nil)
      @source = source || scope.exits_source
    end

    def call
      source
        .reorder(Arel.sql("ahoy_events.visit_id, ahoy_events.time desc, ahoy_events.id desc"))
        .select(Arel.sql(
          "distinct on (ahoy_events.visit_id) ahoy_events.visit_id as visit_id, " \
          "#{AhoyDashboard::Sql::EVENT_PATH} as path"
        ))
    end

    private

    attr_reader :source
  end
end
