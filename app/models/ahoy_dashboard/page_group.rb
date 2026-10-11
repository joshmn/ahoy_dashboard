module AhoyDashboard
  # A rule that folds noisy paths into one name.
  #
  # /blog/2026/a-long-title and forty of its siblings are one thing worth
  # knowing about, and forty rows saying so is a card nobody can read. A group
  # names the pattern once and the Pages card reports the fold.
  #
  # Nothing is rewritten on the way in. The events keep their real paths and the
  # grouping is applied when a card is read, so switching it off shows the paths
  # back exactly as they were and a rule written today folds the whole history.
  class PageGroup < AhoyDashboard::Record
    # A trailing star matches a whole section. Anything else is the path itself.
    # Deliberately not a regular expression: these are typed into a settings form
    # by somebody who wants /blog/* to mean what it looks like, and a pattern
    # language with two rules is one they can hold in their head.
    WILDCARD = "*".freeze
    SEPARATOR = ",".freeze
    MAX_PATTERNS = 20

    validates :name, presence: true, uniqueness: true
    validate :has_a_pattern

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    normalizes :patterns, with: ->(value) { clean(value) }

    scope :ordered, -> { order(:position, :id) }

    # Guarded against a missing table so the dashboard still boots mid-migration.
    def self.listed
      return [] unless Installation.table?(table_name)

      ordered.to_a
    end

    # A comma separated string from the form, or a list from the database. Both
    # arrive here so a rule typed in and a rule read back are the same rule.
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

    # First rule wins, which is what position orders. A path that matches nothing
    # is left as it is, so ungrouped traffic still reads as itself rather than
    # falling into an "Other" bucket nobody asked for.
    def self.for_path(path, rules: listed)
      rules.find { |rule| rule.matches?(path) }
    end

    def matches?(path)
      subject = path.to_s
      return false if subject.blank?

      pattern_list.any? { |pattern| match?(subject, pattern) }
    end

    # The grouping, as SQL over the page path.
    #
    # A case expression rather than a fold over the answer, because the answer is
    # already aggregated and a visitor count cannot be added across rows without
    # counting somebody twice. Grouping here means every metric is computed per
    # group by Postgres and all of them stay correct.
    #
    # Rules are tried in order and the first match wins, which is what a case
    # does anyway. Anything matching nothing falls through to its own path, so
    # ungrouped traffic reads as itself rather than landing in a bucket.
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

    # A trailing star is a prefix match and everything else is the path itself.
    # Both go through Sql.literal, and the prefix has its LIKE metacharacters
    # escaped, so a rule written as /a_b matches /a_b rather than /axb.
    def test_sql(expression, pattern)
      return "#{expression} = #{AhoyDashboard::Sql.literal(pattern)}" unless pattern.end_with?(WILDCARD)

      prefix = pattern.delete_suffix(WILDCARD)
      return nil if prefix.blank?

      escaped = prefix.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
      "#{expression} like #{AhoyDashboard::Sql.literal("#{escaped}%")}"
    end

    def match?(subject, pattern)
      return subject.start_with?(pattern.delete_suffix(WILDCARD)) if pattern.end_with?(WILDCARD)

      subject == pattern
    end

    def has_a_pattern
      return if pattern_list.any?

      errors.add(:patterns, "need at least one path, or the rule matches nothing")
    end
  end
end
