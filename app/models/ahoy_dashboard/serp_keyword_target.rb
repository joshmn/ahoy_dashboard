module AhoyDashboard
  class SerpKeywordTarget < AhoyDashboard::Record
    belongs_to :keyword, class_name: "AhoyDashboard::SerpKeyword", inverse_of: :keyword_targets
    belongs_to :site, class_name: "AhoyDashboard::SerpSite", inverse_of: :keyword_targets

    has_many :checks, class_name: "AhoyDashboard::SerpCheck", foreign_key: :target_id,
             inverse_of: :target, dependent: :destroy

    validates :keyword_id, uniqueness: { scope: :site_id }

    scope :tracked, -> { where(tracking_enabled: true) }

    def to_param
      id.to_s
    end
  end
end
