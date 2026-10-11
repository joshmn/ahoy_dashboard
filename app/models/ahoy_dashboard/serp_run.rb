module AhoyDashboard
  class SerpRun < AhoyDashboard::Record
    enum :status, { pending: 0, success: 1, partial: 2, failed: 3 }, validate: true

    belongs_to :keyword, class_name: "AhoyDashboard::SerpKeyword", inverse_of: :runs

    has_many :run_pages, -> { order(:page_number) }, class_name: "AhoyDashboard::SerpRunPage",
             foreign_key: :run_id, inverse_of: :run, dependent: :destroy
    has_many :checks, class_name: "AhoyDashboard::SerpCheck", foreign_key: :run_id,
             inverse_of: :run, dependent: :destroy
    has_many :ai_citations, -> { order(:slot) }, class_name: "AhoyDashboard::SerpAiCitation",
             foreign_key: :run_id, inverse_of: :run, dependent: :destroy
    has_many :results, -> { order(:position) }, class_name: "AhoyDashboard::SerpResult",
             foreign_key: :run_id, inverse_of: :run, dependent: :destroy

    validates :provider, :query, :location, :checked_at, presence: true

    scope :chronological, -> { order(:checked_at, :id) }
    scope :usable, -> { where(status: [ statuses[:success], statuses[:partial] ]) }
    scope :for_tag, ->(tag) { tag.present? ? where(keyword_id: SerpKeyword.tagged(tag).select(:id)) : all }
    scope :at_current_places, -> {
      where("exists (select 1 from #{SerpKeyword.table_name} current_keyword " \
            "where current_keyword.id = #{table_name}.keyword_id " \
            "and current_keyword.locations @> jsonb_build_array(#{table_name}.location))")
    }

    def place
      Serp::Location.parse(location)
    end

    def usable?
      success? || partial?
    end

    def result
      pages = run_pages.select(&:success?).map(&:result).select { |value| value }
      return nil if pages.empty?

      Serp::Result.combine(pages)
    end

    def to_param
      id.to_s
    end
  end
end
