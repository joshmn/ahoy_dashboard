# frozen_string_literal: true

module AhoyDashboard

  class TrackedKeywordsPresenter
    def initialize(phrases:)
      @keywords = TrackedKeywordsQuery.call(phrases: phrases)
    end

    def id_for(phrase)
      text = phrase.to_s.strip.squeeze(" ").downcase
      keyword = keywords.find { |candidate| candidate.query.downcase == text }

      keyword.id if keyword
    end

    private

    attr_reader :keywords
  end
end
