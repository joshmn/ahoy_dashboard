module AhoyDashboard
  module Seo
    class BacklinkPresenter < BasePresenter
      def tiles
        [
          Tile.new(label: "Referring domains", value: number(result.total_domains), note: net_note, tone: tone_for(result.net)),
          Tile.new(label: "Links", value: number(result.total_links), note: "across those domains", tone: nil),
          Tile.new(label: "Followed", value: percent(result.follow_share), note: "of referring domains", tone: nil),
          Tile.new(label: "New", value: number(result.totals.gained), note: range_label, tone: nil),
          Tile.new(label: "Lost", value: number(result.totals.lost), note: range_label, tone: nil),
          Tile.new(label: "Nofollow", value: number(result.totals.nofollow), note: "pass no authority", tone: nil)
        ]
      end

      def domains_hint
        shown_hint(domains.size, result.totals.domains, "Highest authority first")
      end

      def changes_hint
        shown = gained.size + lost.size
        total = result.totals.gained + result.totals.lost
        shown < total ? "#{range_label}, top #{number(shown)} of #{number(total)}" : range_label
      end

      def nofollow_hint
        shown_hint(nofollow.size, result.totals.nofollow, "Pass no authority")
      end

      def invented?
        any? && result.sample?
      end

      def sample_detail
        "These sites came from sample data, not a real search provider. The next real sync replaces them."
      end

      def net_note
        "#{signed(result.net)} in range"
      end

      def series
        result.series.map { |on, count| [ on_label(on), count ] }
      end

      def domains
        result.domains
      end

      def anchors
        result.anchors
      end

      def pages
        result.pages
      end

      def gained
        result.gained
      end

      def lost
        result.lost
      end

      def nofollow
        result.nofollow
      end

      def enabled?
        ::AhoyDashboard::Backlinks.enabled?
      end

      def available?
        ::AhoyDashboard::Backlinks.available?
      end

      def refusal
        memo(:refusal) { ::AhoyDashboard::Backlinks.refusal }
      end

      def syncable?
        refusal.nil?
      end

      def setup_notice
        case refusal
        when :disabled then AhoyDashboard::SetupNotice.call(:backlinks)
        when :no_host then AhoyDashboard::SetupNotice.call(:backlink_host, url: routes.edit_settings_general_path)
        when :sample then AhoyDashboard::SetupNotice.call(:backlink_sample, url: providers_path)
        when :unsupported then AhoyDashboard::SetupNotice.call(:backlink_provider, url: providers_path)
        when :unconfigured then AhoyDashboard::SetupNotice.call(:provider_credentials, url: providers_path)
        end
      end

      def empty_hint
        return "Press Sync now to pull the sites that link to you." if syncable?

        "Sites that link to you show here once backlinks are ready and the first sync runs."
      end

      def synced_note
        return "Never synced" if result.last_synced_on.nil?

        "Last synced #{on_label(result.last_synced_on)}"
      end

      def sync_path
        routes.seo_backlink_syncs_path
      end

      def sync_reason
        refusal && ::AhoyDashboard::Backlinks.refusal_message(refusal)
      end

      def sync_fix
        return unless %i[sample unsupported unconfigured capped].include?(refusal)

        { label: "Search provider", url: providers_path }
      end

      def authority_known?
        result.authority_known?
      end

      def kinds?
        domains.any? { |domain| domain.kind.present? }
      end

      def kind_label(domain)
        domain.kind.presence&.capitalize || DASH
      end

      def first_seen(domain)
        on_label(domain.first_seen_on)
      end

      def authority_of(domain)
        domain.authority || DASH
      end

      def csv_tables
        [
          CsvTable.new(key: "domains", label: "Sites linking to you", headers: domains_headers) do
            domains.map do |domain|
              values = [ domain.domain, domain.authority, domain.links ]
              values << domain.kind.presence&.capitalize if kinds?
              values + [ csv_date(domain.first_seen_on), domain.nofollow? ? "Nofollow" : "Follow" ]
            end
          end,
          CsvTable.new(key: "anchors", label: "Anchor text", headers: [ "Anchor", "Sites", "Links" ]) do
            anchors.map { |anchor| [ anchor.text, anchor.domains, anchor.links ] }
          end,
          CsvTable.new(key: "changes", label: "New and lost", headers: [ "Domain", "State" ]) do
            gained.map { |domain| [ domain.domain, "New" ] } + lost.map { |domain| [ domain.domain, "Lost" ] }
          end,
          CsvTable.new(key: "nofollow", label: "Nofollow only", headers: [ "Domain", "Authority" ]) do
            nofollow.map { |domain| [ domain.domain, domain.authority ] }
          end
        ]
      end

      def authority_warning
        "Authority is the provider's own score. Every provider scores it differently."
      end

      private

      def domains_headers
        [ "Domain", "Authority", "Links", *("Kind" if kinds?), "First seen", "Follow" ]
      end

      def shown_hint(shown, total, label)
        shown < total ? "#{label}, top #{number(shown)} of #{number(total)}" : label
      end
    end
  end
end
