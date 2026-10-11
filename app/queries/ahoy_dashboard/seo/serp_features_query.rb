module AhoyDashboard
  module Seo
    # What is on the results page besides the results, per search, plus the two
    # pools worth having across all of them: the questions Google decided also
    # get asked, and the searches it suggests next.
    #
    # This costs nothing. It reads the stored copy of readings that were already
    # paid for. What it cannot do is see further back than the trim: a payload
    # stored before a key was worth keeping does not have it, so the page counts
    # what it could read rather than pretending the rest were absent.
    class SerpFeaturesQuery
      Row = Data.define(:keyword, :query, :location, :checked_at, :features, :questions,
                        :searches, :readable) do
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

        def place
          Serp::Location.parse(location)
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

        # Slots on page one with somebody's name on them. Ours against theirs is
        # the whole reason to look at a feature list rather than a feature count.
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
          keyword = keywords[run.keyword_id]
          next if keyword.nil?

          payload = payloads[run.id]
          features, questions, searches = SerpFeatures.from(payload)

          Row.new(keyword: keyword, query: keyword.query, location: run.location,
                  checked_at: run.checked_at, features: features, questions: questions,
                  searches: searches, readable: payload.present?)
        end.select { |value| value }
      end

      # One reading per search and place, the most recent in the range. A feature
      # comes and goes on the same search within a week, so counting every
      # reading would report how often something was polled rather than how much
      # of the page it holds.
      def runs
        @runs ||= AhoyDashboard::SerpRun.usable
          .where(checked_at: range)
          .for_tag(tag)
          .select("distinct on (keyword_id, location) ahoy_dashboard_serp_runs.*")
          .order(Arel.sql("keyword_id, location, checked_at desc, id desc"))
          .to_a
      end

      # The stored answer for each of those readings, joined back on. A run that
      # paged is several rows, and the features live on whichever page carried
      # them, so they merge rather than the first one winning.
      def payloads
        @payloads ||= AhoyDashboard::SerpRunPage
          .where(run_id: runs.map(&:id), status: AhoyDashboard::SerpRunPage.statuses[:success])
          .order(:run_id, :page_number)
          .each_with_object({}) do |page, found|
            response = SerpFeatures.readable(page.response)
            next if response.blank?

            found[page.run_id] = (found[page.run_id] || {}).reverse_merge(response)
          end
      end

      # Every question asked across the whole tracked set, with who is answering
      # it. This is a content list nobody had to think of: Google is naming the
      # questions and naming who it currently believes answers them best.
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

      def keywords
        @keywords ||= AhoyDashboard::SerpKeyword.where(id: runs.map(&:keyword_id).uniq).index_by(&:id)
      end
    end
  end
end
