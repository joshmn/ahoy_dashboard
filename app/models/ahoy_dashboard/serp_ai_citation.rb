module AhoyDashboard
  class SerpAiCitation < AhoyDashboard::Record
    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :ai_citations

    validates :slot, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
    validates :link, :checked_at, presence: true

    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }
  end
end
