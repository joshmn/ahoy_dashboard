module AhoyDashboard
  # One applied filter chip. It knows how to say itself and how to add itself to
  # a relation, and it binds every value rather than writing it into the SQL.
  class Filter
    include ActiveModel::Model

    OPERATORS = {
      "is" => "is",
      "is_not" => "is not",
      "contains" => "contains",
      "not_contains" => "does not contain"
    }.freeze

    DEFAULT_OPERATOR = "is".freeze
    NEGATIVE_OPERATORS = %w[is_not not_contains].freeze

    attr_reader :dimension, :operator, :value

    def initialize(dimension:, value:, operator: DEFAULT_OPERATOR)
      @dimension = dimension
      @operator = OPERATORS.key?(operator.to_s) ? operator.to_s : DEFAULT_OPERATOR
      @value = value.to_s
    end

    def operator_label
      OPERATORS.fetch(operator)
    end

    def negative?
      NEGATIVE_OPERATORS.include?(operator)
    end

    def label
      "#{dimension.filter_label} #{operator_label} #{value}"
    end

    def unknown?
      value == dimension.unknown_label
    end

    def exit?
      dimension.sql.to_s.include?(ExitPagesQuery::ALIAS)
    end

    def to_param
      { "dimension" => dimension.key, "operator" => operator, "value" => value }
    end

    def apply(relation, sql: dimension.sql)
      relation.where(Arel.sql(predicate(sql: sql)))
    end

    def predicate(sql: dimension.sql)
      case operator
      when "is_not" then negated(sql)
      when "contains" then "(#{sql} ILIKE #{quote(term)})"
      when "not_contains" then "(#{sql} IS NULL OR #{sql} NOT ILIKE #{quote(term)})"
      else exact(sql)
      end
    end

    def candidate_predicate(sql: dimension.sql)
      return predicate(sql: sql) unless dimension.page_views_only?

      "(ahoy_events.name = #{quote(AhoyDashboard::PAGE_VIEW)} AND #{predicate(sql: sql)})"
    end

    private

    # A filter value is somebody's own text, so its % and _ are characters rather
    # than wildcards. FilterOptionsQuery already escapes them for the typeahead,
    # and the two have to agree: picking a value with an underscore out of the
    # dropdown matched more rows than the dropdown had offered.
    def term
      "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
    end

    def quote(text)
      AhoyDashboard.visit.connection.quote(text)
    end

    def exact(sql)
      return "(#{sql} IS NULL OR #{sql} = '')" if unknown?
      predicate = Sql::CHANNEL_PREDICATES[value] if sql == Sql::CHANNEL
      return "(#{predicate})" if predicate

      "(#{sql} = #{quote(value)})"
    end

    # "is not (not set)" means drop the rows that have nothing, which is the one
    # case IS DISTINCT FROM gets backwards: it keeps every NULL.
    def negated(sql)
      return "(#{sql} IS NOT NULL AND #{sql} <> '')" if unknown?
      predicate = Sql::CHANNEL_PREDICATES[value] if sql == Sql::CHANNEL
      return "(not (#{predicate}))" if predicate

      "(#{sql} IS DISTINCT FROM #{quote(value)})"
    end
  end
end
