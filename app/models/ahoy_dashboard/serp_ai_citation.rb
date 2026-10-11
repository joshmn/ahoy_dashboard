module AhoyDashboard
  class SerpAiCitation < AhoyDashboard::Record
    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :ai_citations

    validates :slot, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
    validates :link, :checked_at, presence: true

    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }

    scope :chronological, -> { order(:checked_at, :slot) }
    scope :in_range, ->(range) { where(checked_at: range) }
    scope :for_tag, ->(tag) { tag.present? ? where(run_id: SerpRun.for_tag(tag).select(:id)) : all }
  end
end
