module AhoyDashboard
  class PageGroup < AhoyDashboard::Record
    include Positioned

    WILDCARD = "*".freeze
    SEPARATOR = ",".freeze
    MAX_PATTERNS = 20

    validates :name, presence: true, uniqueness: true
    validate :has_a_pattern

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    normalizes :patterns, with: ->(value) { clean(value) }

    after_save :forget
    after_destroy :forget

    def self.listed
      return [] unless Installation.table?(table_name)

      ordered.to_a
    end

    def self.clean(value)
      list = value.is_a?(String) ? value.split(SEPARATOR) : Array(value)

      list.map { |pattern| pattern.to_s.strip }.reject(&:blank?).uniq.first(MAX_PATTERNS)
    end

    def pattern_list
      Array(patterns)
    end

    def to_s
      name
    end

    def self.match_case_sql(expression, rules: listed)
      whens = rules.map { |rule| rule.when_sql(expression) }.select { |value| value }
      return nil if whens.empty?

      Arel.sql("case #{whens.join(" ")} else #{expression} end")
    end

    def when_sql(expression)
      tests = pattern_list.map { |pattern| test_sql(expression, pattern) }.select { |value| value }
      return nil if tests.empty?

      "when (#{tests.join(" or ")}) then #{AhoyDashboard::Sql.literal(name)}"
    end

    private

    def test_sql(expression, pattern)
      return "#{expression} = #{AhoyDashboard::Sql.literal(pattern)}" unless pattern.end_with?(WILDCARD)

      prefix = pattern.delete_suffix(WILDCARD)
      return nil if prefix.blank?

      escaped = ActiveRecord::Base.sanitize_sql_like(prefix)
      "#{expression} like #{AhoyDashboard::Sql.literal("#{escaped}%")}"
    end

    def forget
      AhoyDashboard::Current.forget_dimensions
    end

    def has_a_pattern
      return if pattern_list.any?

      errors.add(:patterns, "need at least one path, or the rule matches nothing")
    end
  end
end
