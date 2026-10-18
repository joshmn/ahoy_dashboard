module AhoyDashboard
  class SerpRun < AhoyDashboard::Record
    include Serp::Searched

    enum :status, { pending: 0, success: 1, partial: 2, failed: 3 }, validate: true

    belongs_to :keyword, class_name: "AhoyDashboard::SerpKeyword", inverse_of: :runs

    has_many :run_pages, -> { order(:page_number) }, class_name: "AhoyDashboard::SerpRunPage",
             foreign_key: :run_id, inverse_of: :run, dependent: :delete_all
    has_many :checks, class_name: "AhoyDashboard::SerpCheck", foreign_key: :run_id,
             inverse_of: :run, dependent: :delete_all
    has_many :ai_citations, -> { order(:slot) }, class_name: "AhoyDashboard::SerpAiCitation",
             foreign_key: :run_id, inverse_of: :run, dependent: :delete_all
    has_many :results, -> { order(:position) }, class_name: "AhoyDashboard::SerpResult",
             foreign_key: :run_id, inverse_of: :run, dependent: :delete_all

    validates :provider, :query, :location, :checked_at, presence: true

    scope :usable, -> { where(status: [ statuses[:success], statuses[:partial] ]) }

    def usable?
      success? || partial?
    end

    def result
      pages = run_pages.select(&:success?).map(&:result).select { |value| value }
      return nil if pages.empty?

      Serp::Result.combine(pages)
    end
  end
end
