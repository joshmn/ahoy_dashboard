module AhoyDashboard
  module Seo
    # Us against every other site being tracked, search by search. This costs
    # nothing to run because it was already paid for: one search is fetched once
    # and every site attached to it is scored off the same page, so a rival is a
    # row in serp_sites rather than a second bill.
    #
    # Four buckets. Missing is the one worth opening the page for.
    class KeywordGapQuery
      BUCKETS = %i[missing weak strong alone nobody].freeze

      Standing = Data.define(:site, :position, :url, :tracked) do
        def ranked?
          position.present?
        end

        def tracked?
          tracked
        end
      end

      Row = Data.define(:keyword, :query, :location, :ours, :rivals) do
        def ranked?
          ours&.ranked?
        end

        def position
          ours&.position
        end

        def contenders
          rivals.select(&:ranked?)
        end

        def best_rival
          contenders.min_by(&:position)
        end

        def gap
          return nil if position.nil? || best_rival.nil?

          best_rival.position - position
        end

        def bucket
          return :nobody if !ranked? && contenders.empty?
          return :missing if !ranked?
          return :alone if contenders.empty?

          position < best_rival.position ? :strong : :weak
        end

        def place
          Serp::Location.parse(location)
        end
      end

      Result = Data.define(:site, :rivals, :range, :rows) do
        def any?
          rows.any?
        end

        def in_bucket(bucket)
          rows.select { |row| row.bucket == bucket }
        end

        def count_of(bucket)
          in_bucket(bucket).size
        end

        def missing
          in_bucket(:missing).sort_by { |row| row.best_rival&.position.to_i }
        end

        def weak
          in_bucket(:weak).sort_by { |row| row.gap.to_i }
        end

        def strong
          in_bucket(:strong).sort_by { |row| -row.gap.to_i }
        end

        def alone
          in_bucket(:alone)
        end

        def nobody
          in_bucket(:nobody)
        end

        def attached
          rivals.select do |rival|
            rows.any? { |row| row.rivals.any? { |stand| stand.site.id == rival.id && stand.tracked? } }
          end
        end

        # How much of the tracked set each rival actually turns up for, which is
        # the only honest way to say whether a rival is a rival.
        def presence
          rivals.map do |rival|
            appearances = rows.count { |row| row.rivals.any? { |stand| stand.site.id == rival.id && stand.ranked? } }

            [ rival, appearances, rows.empty? ? 0.0 : appearances.to_f / rows.size ]
          end.sort_by { |_rival, appearances, _share| -appearances }
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, tag: nil)
        @site = site
        @range = range
        @tag = tag
      end

      def call
        return Result.new(site: site, rivals: rivals, range: range, rows: []) if site.nil?

        Result.new(site: site, rivals: rivals, range: range, rows: rows)
      end

      private

      attr_reader :site, :range, :tag

      def rivals
        @rivals ||= AhoyDashboard::SerpSite.ordered.reject { |candidate| candidate.id == site&.id }
      end

      def rows
        pairs.map do |keyword_id, location|
          keyword = keywords[keyword_id]
          next if keyword.nil?

          Row.new(keyword: keyword, query: keyword.query, location: location,
                  ours: standing_for(site, keyword_id, location),
                  rivals: rivals.map { |rival| standing_for(rival, keyword_id, location) })
        end.select { |value| value }
      end

      def standing_for(candidate, keyword_id, location)
        check = latest[[ candidate&.id, keyword_id, location ]]

        Standing.new(site: candidate, position: check&.position, url: check&.url,
                     tracked: check.present? || targets.include?([ keyword_id, candidate&.id ]))
      end

      def targets
        @targets ||= AhoyDashboard::SerpKeywordTarget.tracked
          .where(keyword_id: pairs.map(&:first).uniq).pluck(:keyword_id, :site_id).to_set
      end

      # Every search either side turned up for, so a search only the rival is
      # tracked on still gets a row rather than being dropped for having no
      # reading of ours.
      def pairs
        @pairs ||= latest.keys.map { |_site_id, keyword_id, location| [ keyword_id, location ] }.uniq
      end

      def latest
        @latest ||= AhoyDashboard::SerpCheck
          .where(status: AhoyDashboard::SerpCheck.statuses[:success])
          .in_range(range)
          .for_tag(tag)
          .select("distinct on (site_id, keyword_id, location) ahoy_dashboard_serp_checks.*")
          .order(Arel.sql("site_id, keyword_id, location, checked_at desc, id desc"))
          .index_by { |check| [ check.site_id, check.keyword_id, check.location ] }
      end

      def keywords
        @keywords ||= AhoyDashboard::SerpKeyword.where(id: pairs.map(&:first).uniq).index_by(&:id)
      end
    end
  end
end
