module AhoyDashboard
  class SerpCheck < AhoyDashboard::Record
    enum :status, { success: 0, failed: 1 }, validate: true

    belongs_to :run, class_name: "AhoyDashboard::SerpRun", inverse_of: :checks
    belongs_to :keyword, class_name: "AhoyDashboard::SerpKeyword", inverse_of: :checks
    belongs_to :target, class_name: "AhoyDashboard::SerpKeywordTarget", inverse_of: :checks
    belongs_to :site, class_name: "AhoyDashboard::SerpSite", inverse_of: :checks

    validates :checked_at, :location, presence: true

    scope :chronological, -> { order(:checked_at, :id) }
    scope :latest_first, -> { order(checked_at: :desc, id: :desc) }
    scope :in_range, ->(range) { where(checked_at: range) }
    scope :for_tag, ->(tag) { tag.present? ? where(keyword_id: SerpKeyword.tagged(tag).select(:id)) : all }
    scope :at, ->(location) { location.present? ? where(location: location) : all }
    scope :at_current_places, -> {
      where("exists (select 1 from #{SerpKeyword.table_name} current_keyword " \
            "where current_keyword.id = #{table_name}.keyword_id " \
            "and current_keyword.locations @> jsonb_build_array(#{table_name}.location))")
    }

    def ranked?
      position.present?
    end

    def place
      Serp::Location.parse(location)
    end

    def to_param
      id.to_s
    end
  end
end
