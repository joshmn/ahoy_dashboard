module AhoyDashboard
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

    def self.operator_options
      OPERATORS.map { |key, text| [ text, key ] }
    end

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
      dimension.exits?
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

      "(#{Sql::PAGE_VIEW_EVENT} AND #{predicate(sql: sql)})"
    end

    private

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

    def negated(sql)
      return "(#{sql} IS NOT NULL AND #{sql} <> '')" if unknown?
      predicate = Sql::CHANNEL_PREDICATES[value] if sql == Sql::CHANNEL
      return "(not (#{predicate}))" if predicate

      "(#{sql} IS DISTINCT FROM #{quote(value)})"
    end
  end
end
