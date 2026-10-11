module AhoyDashboard
  module Alerts
    # Every rule the dashboard knows how to evaluate.
    #
    # A registry rather than rows somebody writes, because a rule is code: the
    # threshold is configurable and the question is not. That also means a rule
    # added in a new version appears for everybody without a migration, and a
    # rule removed stops firing rather than sitting there evaluating nothing.
    module Catalogue
      GROUPS = {
        rank: "Rank tracking",
        spend: "Spending",
        search_console: "Search Console",
        goals: "Goals",
        backlinks: "Backlinks",
        jobs: "Jobs",
        traffic: "Traffic"
      }.freeze

      REQUIRES = {
        rank: %i[serp],
        spend: %i[serp keywords backlinks],
        search_console: %i[search_console],
        backlinks: %i[backlinks]
      }.freeze

      RULES = %w[
        LostFromResults OffPageOne BigDrop Overtaken OverviewAppeared CitationLost
        SpendNearCap
        SearchClicksFell ImpressionsFell
        GoalStopped GoalConversionsFell
        BacklinksLost
        JobFailed JobStopped
        TrafficSpike TrafficDrop
      ].freeze

      def self.all
        RULES.map { |name| Rules.const_get(name).definition }
      end

      def self.keys
        all.map(&:key)
      end

      def self.available
        all.select(&:available?)
      end

      def self.unavailable_keys
        all.reject(&:available?).map(&:key)
      end

      def self.find(key)
        all.find { |definition| definition.key == key.to_s }
      end

      def self.grouped(rules, available_only: false)
        rules = rules.select(&:available?) if available_only

        GROUPS.map do |group, name|
          members = rules.select { |rule| rule.definition&.group == group }
          [ name, members ] if members.any?
        end.select { |value| value }
      end
    end
  end
end
