# frozen_string_literal: true

module AhoyDashboard

  class TrackedKeywordsQuery
    class << self
      def call(phrases:)
        new(phrases: phrases).call
      end
    end

    def initialize(phrases:)
      @phrases = phrases.map { |phrase| phrase.to_s.strip.squeeze(" ").downcase }.reject(&:empty?).uniq
    end

    def call
      return [] if phrases.empty? || !Serp.installed?

      SerpKeyword
        .where("lower(query) IN (?)", phrases)
        .select("DISTINCT ON (lower(query)) id, query")
        .order(Arel.sql(preference))
        .to_a
    end

    private

    attr_reader :phrases

    def preference
      connection = SerpKeyword.connection
      device = connection.quote(Serp::DEFAULT_DEVICE)
      language = connection.quote(Serp::DEFAULT_LANGUAGE)

      "lower(query), CASE WHEN device = #{device} THEN 0 ELSE 1 END, " \
        "CASE WHEN language = #{language} THEN 0 ELSE 1 END, id"
    end
  end
end
