module AhoyDashboard
  # One referring domain, not one link. A site linking four hundred times out of
  # a footer is one relationship, and counting the links makes it look like four
  # hundred.
  #
  # A domain that stops linking keeps its row and gets a lost_on. That is the
  # single most useful thing this table holds and a delete throws it away.
  class BacklinkDomain < AhoyDashboard::Record
    self.table_name = "ahoy_dashboard_backlink_domains"

    validates :domain, :first_seen_on, :last_seen_on, :provider, presence: true
    validates :domain, uniqueness: true

    normalizes :domain, with: ->(value) { Serp::Domain.host(value) }

    scope :live, -> { where(lost_on: nil) }
    scope :lost, -> { where.not(lost_on: nil) }
    scope :by_authority, -> { order(Arel.sql("authority desc nulls last, links desc")) }
    scope :gained_since, ->(date) { live.where(arel_table[:first_seen_on].gteq(date)) }
    scope :lost_since, ->(date) { where(arel_table[:lost_on].gteq(date)) }

    def lost?
      lost_on.present?
    end

    def nofollow?
      !follow
    end

    def to_param
      id.to_s
    end
  end
end
