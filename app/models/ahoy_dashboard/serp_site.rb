module AhoyDashboard
  class SerpSite < AhoyDashboard::Record
    has_many :keyword_targets, class_name: "AhoyDashboard::SerpKeywordTarget", foreign_key: :site_id,
             inverse_of: :site, dependent: :delete_all
    has_many :keywords, through: :keyword_targets
    has_many :checks, class_name: "AhoyDashboard::SerpCheck", foreign_key: :site_id,
             inverse_of: :site, dependent: :delete_all

    normalizes :name, with: ->(value) { value.to_s.strip.presence }
    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }

    validates :name, presence: true
    validates :domain, presence: true, uniqueness: true

    scope :ordered, -> { order(:name, :id) }

    def self.ours
      find_by(domain: Serp.own_domain)
    end

    def self.own_first
      ordered.to_a.partition(&:ours?).flatten
    end

    def ours?
      domain.present? && domain == Serp.own_domain
    end
  end
end
