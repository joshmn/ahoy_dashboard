module AhoyDashboard
  class SerpCheck < AhoyDashboard::Record
    include Serp::Searched

    enum :status, { success: 0, failed: 1 }, validate: true

    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :checks
    belongs_to :keyword, class_name: "AhoyDashboard::SerpKeyword", inverse_of: :checks
    belongs_to :target, class_name: "AhoyDashboard::SerpKeywordTarget", inverse_of: :checks
    belongs_to :site, class_name: "AhoyDashboard::SerpSite", inverse_of: :checks

    validates :checked_at, :location, presence: true

    scope :chronological, -> { order(:checked_at, :id) }
    scope :latest_first, -> { order(checked_at: :desc, id: :desc) }
    scope :in_range, ->(range) { where(checked_at: range) }

    def ranked?
      position.present?
    end
  end
end
