module AhoyDashboard
  module Seo
    class SerpFeaturesQuery
      Row = Data.define(:keyword, :location, :checked_at, :features, :questions, :searches, :readable) do
        include Serp::Placed

        def query
          keyword.query
        end

        def readable?
          readable
        end

        def has?(key)
          features.any? { |feature| feature.key == key }
        end

        def owner_of(key)
          features.find { |feature| feature.key == key }&.owner
        end

        def owners_of(key)
          features.find { |feature| feature.key == key }&.owners || []
        end

        def keys
          features.map(&:key)
        end
      end

      Asked = Data.define(:text, :times, :answers) do
        def top
          answers.max_by { |_domain, count| count }&.first
        end
      end

      Suggested = Data.define(:text, :times)

      Result = Data.define(:site, :range, :rows, :questions, :searches) do
        def any?
          rows.any?
        end

        def readable
          rows.select(&:readable?)
        end

        def blind
          rows.reject(&:readable?)
        end

        def counts
          SerpFeatures::CATALOGUE.keys.map do |key|
            seen = readable.count { |row| row.has?(key) }
            next if seen.zero?

            [ key, SerpFeatures.label(key), seen, readable.empty? ? 0.0 : seen.to_f / readable.size ]
          end.select { |value| value }
        end

        def ours(key)
          return 0 if site.nil?

          readable.count { |row| mine?(row.owner_of(key)) }
        end

        def mine?(domain)
          return false if site.nil? || domain.blank?

          Serp::Domain.matches?(domain, site.domain, match_subdomains: site.match_subdomains)
        end

        def snippets_held
          ours("featured_snippet")
        end

        def clean?
          blind.empty?
        end

        def unreadable?
          rows.any? && readable.empty?
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
        built = rows

        Result.new(site: site, range: range, rows: built, questions: pooled(built),
                   searches: suggested(built))
      end

      private

      attr_reader :site, :range, :tag

      def rows
        @rows ||= runs.map do |run|
          payload = payloads[run.id]
          reading = SerpFeatures.from(payload)

          Row.new(keyword: run.keyword, location: run.location, checked_at: run.checked_at,
                  features: reading.features, questions: reading.questions, searches: reading.searches,
                  readable: payload.present?)
        end
      end

      def runs
        @runs ||= AhoyDashboard::SerpRun.usable
          .where(checked_at: range)
          .for_tag(tag)
          .at_current_places
          .latest_per_search
          .includes(:keyword)
          .to_a
      end

      def payloads
        @payloads ||= AhoyDashboard::SerpRunPage.success
          .where(run_id: runs.map(&:id))
          .order(:run_id, :page_number)
          .select(:run_id, :response)
          .each_with_object({}) do |page, found|
            response = SerpFeatures.readable(page.response)
            next if response.blank?

            found[page.run_id] = (found[page.run_id] || {}).reverse_merge(response)
          end
      end

      def pooled(built)
        built.flat_map(&:questions).group_by { |question| question.text.downcase }
          .map do |_key, group|
            answers = group.map(&:domain).select { |value| value }.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }

            Asked.new(text: group.first.text, times: group.size, answers: answers)
          end
          .sort_by { |asked| [ -asked.times, asked.text ] }
      end

      def suggested(built)
        built.flat_map(&:searches).map(&:downcase).each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
          .map { |text, times| Suggested.new(text: text, times: times) }
          .sort_by { |row| [ -row.times, row.text ] }
      end
    end
  end
end
