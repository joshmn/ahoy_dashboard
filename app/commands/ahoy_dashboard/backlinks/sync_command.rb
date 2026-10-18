module AhoyDashboard
  module Backlinks
    class SyncCommand < AhoyDashboard::Command
      Outcome = Data.define(:domains, :gained, :lost, :returned)
      REFRESHED = %i[authority links follow kind top_page last_seen_on lost_on provider].freeze

      SAMPLE_PROVIDER = "fake".freeze

      def initialize(domain: nil, limit: 500, now: Time.current)
        @domain = domain.presence || Backlinks.domain
        @limit = limit
        @now = now
        @today = now.to_date
      end

      def call
        blocker = Backlinks.refusal(domain: domain)
        return refuse(blocker) if blocker

        @adapter = Backlinks.adapter
        return broadcast(:capped, record) unless spend.reserve

        answer = adapter.backlinks(domain: domain, limit: limit)
        outcome = store(answer, adapter.provider_name.to_s)
        spend.settle(adapter.units_used, used: true)

        broadcast(:ok, outcome)
      rescue Serp::QuotaError => e
        broken(e)
        broadcast(:rate_limited, e.message)
      rescue Serp::Error => e
        broken(e)
        broadcast(:failed, e.message)
      ensure
        @spend&.settle(adapter&.units_used)
      end

      private

      attr_reader :domain, :limit, :now, :today, :adapter

      def refuse(blocker)
        case blocker
        when :disabled then broadcast(:disabled)
        when :no_host then broadcast(:invalid, "no domain to look up")
        when :unsupported then broadcast(:unsupported, Backlinks.provider)
        when :capped then broadcast(:capped, record)
        else broadcast(:refused, Backlinks.refusal_message(blocker))
        end
      end

      def record
        @record ||= Backlinks.record
      end

      def spend
        @spend ||= Serp::Spend.new(provider: record, units: adapter.class.backlink_cost_units,
                                   kind: :backlinks, name: adapter.class.adapter_name, now: now)
      end

      def broken(error)
        record&.record_error!(error.message)
      end

      def store(answer, provider)
        referrers = Array(answer[:domains]).select { |referrer| referrer.domain.present? }.uniq(&:domain)

        AhoyDashboard::BacklinkDomain.transaction do
          forget_samples(provider)
          outcome = reconcile(referrers, provider, complete: complete?(referrers, answer[:total]))
          record_anchors(answer[:anchors])
          sample(outcome, provider)
          outcome
        end
      end

      def complete?(referrers, total)
        return referrers.size >= total.to_i if total

        referrers.size < limit.to_i
      end

      def forget_samples(provider)
        return if provider == SAMPLE_PROVIDER
        return unless AhoyDashboard::BacklinkDomain.where(provider: SAMPLE_PROVIDER).exists? ||
                      AhoyDashboard::BacklinkSample.where(provider: SAMPLE_PROVIDER).exists?

        AhoyDashboard::BacklinkDomain.where(provider: SAMPLE_PROVIDER).delete_all
        AhoyDashboard::BacklinkSample.where(provider: SAMPLE_PROVIDER).delete_all
        AhoyDashboard::BacklinkAnchor.delete_all
      end

      def reconcile(referrers, provider, complete:)
        seen = referrers.map(&:domain).to_set
        stored = AhoyDashboard::BacklinkDomain.where(domain: seen.to_a).pluck(:domain, :lost_on).to_h
        rows = referrers.map { |referrer| attributes(referrer, provider) }

        AhoyDashboard::BacklinkDomain.upsert_all(rows, unique_by: :domain, update_only: REFRESHED) if rows.any?
        lost = gone(referrers, seen, complete).update_all(lost_on: today, updated_at: now)

        Outcome.new(domains: seen.size, gained: seen.count { |domain| !stored.key?(domain) },
                    lost: lost, returned: stored.values.count(&:present?))
      end

      def gone(referrers, seen, complete)
        unseen = AhoyDashboard::BacklinkDomain.live.where.not(domain: seen.to_a)
        return unseen if complete

        cutoff = referrers.map(&:authority).select { |value| value }.min
        cutoff ? unseen.where("authority > ?", cutoff) : unseen.none
      end

      def attributes(referrer, provider)
        {
          domain: referrer.domain, authority: referrer.authority, links: referrer.links,
          follow: referrer.follow, kind: referrer.kind, top_page: referrer.top_page,
          first_seen_on: referrer.first_seen_on || today, last_seen_on: today, lost_on: nil, provider: provider
        }
      end

      def record_anchors(anchors)
        return if anchors.nil?

        rows = Array(anchors).map { |anchor|
          { text: anchor.text.to_s.first(255), links: anchor.links, domains: anchor.domains,
            seen_on: today, created_at: now, updated_at: now }
        }.select { |row| row[:text].present? }.uniq { |row| row[:text] }

        AhoyDashboard::BacklinkAnchor.where.not(text: rows.pluck(:text)).delete_all
        return if rows.empty?

        AhoyDashboard::BacklinkAnchor.upsert_all(rows, unique_by: :text,
                                                       update_only: %i[links domains seen_on])
      end

      def sample(outcome, provider)
        live = AhoyDashboard::BacklinkDomain.live

        AhoyDashboard::BacklinkSample.upsert(
          { on: today, domains: live.count, links: live.sum(:links),
            follow_domains: live.where(follow: true).count, gained: outcome.gained,
            lost: outcome.lost, provider: provider,
            created_at: Time.current, updated_at: Time.current },
          unique_by: :on
        )
      end
    end
  end
end
