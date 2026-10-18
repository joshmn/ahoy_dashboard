module AhoyDashboard
  class BacklinkDomain < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_backlink_domains"

    validates :domain, :first_seen_on, :last_seen_on, :provider, presence: true
    validates :domain, uniqueness: true

    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }

    scope :live, -> { where(lost_on: nil) }
    scope :by_authority, -> { order(Arel.sql("authority desc nulls last, links desc")) }
    scope :gained_since, ->(date) { live.where(arel_table[:first_seen_on].gteq(date)) }
    scope :lost_since, ->(date) { where(arel_table[:lost_on].gteq(date)) }

    def lost?
      lost_on.present?
    end

    def nofollow?
      !follow
    end
  end
end
