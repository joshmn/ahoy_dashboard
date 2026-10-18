module AhoyDashboard
  module DigestRecord
    extend ActiveSupport::Concern

    CLAIM_TIMEOUT = 30.minutes

    included do
      enum :period, { daily: 0, weekly: 1, monthly: 2 }, validate: true

      validates :starts_on, :ends_on, presence: true
    end

    def claimable?
      !done? && (!sending? || updated_at.before?(CLAIM_TIMEOUT.ago))
    end

    def window
      Digests::Window.new(period: period.to_sym, starts_on: starts_on, ends_on: ends_on)
    end
  end
end
