module AhoyDashboard
  module SearchConsole
    # Every property this account can actually read, which is what the picker
    # lists.
    class SitesService < BaseService
      UNVERIFIED = "siteUnverifiedUser".freeze

      Site = Data.define(:url, :permission) do
        def domain?
          url.to_s.start_with?(GoogleAccount::DOMAIN_PREFIX)
        end

        def label
          domain? ? url.delete_prefix(GoogleAccount::DOMAIN_PREFIX) : url
        end
      end

      def initialize(account: nil)
        @account = account || GoogleAccount.current
      end

      # Unverified properties are dropped rather than shown greyed out: Search
      # Analytics answers 403 for them, so listing one would only be an offer to
      # break the sync.
      def call
        payload = get_json(SearchConsole::SITES_URL, AccessTokenService.call(account: account))

        payload.fetch("siteEntry", [])
          .reject { |entry| entry["permissionLevel"] == UNVERIFIED }
          .map { |entry| build(entry) }.select { |value| value }
          .sort_by { |site| [ site.domain? ? 0 : 1, site.label ] }
      end

      private

      attr_reader :account

      def build(entry)
        url = entry["siteUrl"]
        return nil if url.blank?

        Site.new(url: url, permission: entry["permissionLevel"])
      end
    end
  end
end
