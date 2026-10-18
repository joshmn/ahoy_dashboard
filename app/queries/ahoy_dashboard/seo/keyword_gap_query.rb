module AhoyDashboard
  module Seo
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

      Row = Data.define(:keyword, :location, :ours, :rivals) do
        include Serp::Placed

        def query
          keyword.query
        end

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
        pairs.map do |keyword, location|
          Row.new(keyword: keyword, location: location, ours: standing_for(site, keyword.id, location),
                  rivals: rivals.map { |rival| standing_for(rival, keyword.id, location) })
        end
      end

      def standing_for(candidate, keyword_id, location)
        check = latest[[ candidate&.id, keyword_id, location ]]

        Standing.new(site: candidate, position: check&.position, url: check&.url,
                     tracked: check.present? || targets.include?([ keyword_id, candidate&.id ]))
      end

      def targets
        @targets ||= AhoyDashboard::SerpKeywordTarget.tracked
          .where(keyword_id: pairs.map { |keyword, _location| keyword.id }.uniq).pluck(:keyword_id, :site_id).to_set
      end

      def pairs
        @pairs ||= latest.values.map { |check| [ check.keyword, check.location ] }.uniq
      end

      def latest
        @latest ||= AhoyDashboard::SerpCheck.success
          .where(site_id: [ site.id, *rivals.map(&:id) ])
          .in_range(range)
          .for_tag(tag)
          .at_current_places
          .select("distinct on (site_id, keyword_id, location) ahoy_dashboard_serp_checks.*")
          .order(Arel.sql("site_id, keyword_id, location, checked_at desc, id desc"))
          .includes(:keyword)
          .index_by { |check| [ check.site_id, check.keyword_id, check.location ] }
      end
    end
  end
end
