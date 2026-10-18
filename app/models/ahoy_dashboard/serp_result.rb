module AhoyDashboard
  class SerpResult < AhoyDashboard::Record
    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :results

    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
    validates :link, :checked_at, presence: true

    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }

    scope :ranked, -> { order(:position) }
    scope :top, ->(depth) { where(arel_table[:position].lteq(depth)) }
  end
end
