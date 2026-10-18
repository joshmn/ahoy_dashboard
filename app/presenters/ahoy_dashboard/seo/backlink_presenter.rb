module AhoyDashboard
  module Seo
    class BacklinkPresenter < BasePresenter
      STEPS = {
        disabled: :backlinks, no_host: :backlink_host, sample: :backlink_sample,
        unsupported: :backlink_provider, unconfigured: :provider_credentials
      }.freeze

      delegate :domains, :anchors, :gained, :lost, :nofollow, :authority_known?, to: :result
      delegate :refusal, :setup_notice, to: :gate
      delegate :reason, :fix, to: :gate, prefix: :sync

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

      def empty_hint
        return "Press Sync now to pull the sites that link to you." if gate.open?

        "Sites that link to you show here once backlinks are ready and the first sync runs."
      end

      def synced_note
        return "Never synced" if result.last_synced_on.nil?

        "Last synced #{on_label(result.last_synced_on)}"
      end

      def sync_path
        routes.seo_backlink_syncs_path
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

      def gate
        memo(:gate) do
          ProviderGate.new(::AhoyDashboard::Backlinks, steps: STEPS, providers_path: providers_path,
                           urls: { no_host: routes.edit_settings_general_path })
        end
      end

      def domains_headers
        [ "Domain", "Authority", "Links", *("Kind" if kinds?), "First seen", "Follow" ]
      end

      def shown_hint(shown, total, label)
        shown < total ? "#{label}, top #{number(shown)} of #{number(total)}" : label
      end
    end
  end
end
