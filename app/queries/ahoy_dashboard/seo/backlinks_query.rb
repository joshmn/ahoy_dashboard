module AhoyDashboard
  module Seo
    class BacklinksQuery
      Totals = Data.define(:domains, :links, :followed, :gained, :lost, :nofollow)

      Result = Data.define(:range, :domains, :series, :anchors, :gained, :lost, :nofollow,
                           :last_synced_on, :provider, :totals, :sample) do
        def any?
          domains.any? || series.any?
        end

        def sample?
          sample
        end

        def live
          domains.reject(&:lost?)
        end

        def total_domains
          totals.domains
        end

        def total_links
          totals.links
        end

        def follow_share
          return 0.0 if totals.domains.zero?

          totals.followed.to_f / totals.domains
        end

        def net
          totals.gained - totals.lost
        end

        def authority_known?
          live.any? { |domain| domain.authority.present? }
        end
      end

      LIMIT = 40
      CHANGES_LIMIT = 15
      NOFOLLOW_LIMIT = 10
      SAMPLE_PROVIDER = "fake".freeze

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:)
        @range = range
      end

      def call
        Result.new(range: range, domains: domains, series: series, anchors: anchors,
                   gained: gained, lost: lost, nofollow: nofollow,
                   last_synced_on: last_sample&.on, provider: last_sample&.provider,
                   totals: totals, sample: sample?)
      end

      private

      attr_reader :range

      def since
        range.begin.to_date
      end

      def live
        AhoyDashboard::BacklinkDomain.live
      end

      def domains
        @domains ||= live.by_authority.limit(LIMIT).to_a
      end

      def series
        AhoyDashboard::BacklinkSample.in_range(range).chronological
          .pluck(:on, :domains).map { |on, count| [ on, count ] }
      end

      def anchors
        AhoyDashboard::BacklinkAnchor.ordered.limit(10).to_a
      end

      def gained
        AhoyDashboard::BacklinkDomain.gained_since(since).by_authority.limit(CHANGES_LIMIT).to_a
      end

      def lost
        AhoyDashboard::BacklinkDomain.lost_since(since).by_authority.limit(CHANGES_LIMIT).to_a
      end

      # Not a toxicity score. Nothing here can tell a bad link from a good one,
      # and a vendor that says it can is selling a guess. What it can say is
      # which of them pass no authority at all, which is a fact.
      def nofollow
        live.where(follow: false).by_authority.limit(NOFOLLOW_LIMIT).to_a
      end

      def totals
        count, links, followed, gained, lost = domain_totals

        Totals.new(domains: count.to_i, links: links.to_i, followed: followed.to_i,
                   gained: gained.to_i, lost: lost.to_i,
                   nofollow: count.to_i - followed.to_i)
      end

      def sample?
        domain_totals.last ||
          AhoyDashboard::BacklinkSample.in_range(range).where(provider: SAMPLE_PROVIDER).exists?
      end

      def domain_totals
        @domain_totals ||= begin
          sql = AhoyDashboard::BacklinkDomain.sanitize_sql_array([ <<~SQL.squish, since, since, SAMPLE_PROVIDER ])
            count(*) filter (where lost_on is null) AS dash_domains,
            coalesce(sum(links) filter (where lost_on is null), 0) AS dash_links,
            count(*) filter (where lost_on is null and follow) AS dash_followed,
            count(*) filter (where lost_on is null and first_seen_on >= ?) AS dash_gained,
            count(*) filter (where lost_on >= ?) AS dash_lost,
            coalesce(bool_or(provider = ?), false) AS dash_sample
          SQL

          AhoyDashboard::BacklinkDomain.pick(Arel.sql(sql))
        end
      end

      def last_sample
        @last_sample ||= AhoyDashboard::BacklinkSample.chronological.last
      end
    end
  end
end
