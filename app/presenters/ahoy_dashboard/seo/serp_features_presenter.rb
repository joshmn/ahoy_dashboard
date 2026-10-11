module AhoyDashboard
  module Seo
    class SerpFeaturesPresenter < BasePresenter
      QUESTIONS_SHOWN = 6
      SEARCHES_SHOWN = 12
      POOL_LIMIT = 100
      ASKED = "people_also_ask".freeze
      SHARE_FLOOR = 3

      SHORT = {
        "featured_snippet" => "Snippet",
        "ai_overview" => "AI",
        "knowledge_graph" => "Panel",
        "people_also_ask" => "Asked",
        "local_pack" => "Local",
        "top_stories" => "News",
        "video" => "Video",
        "images" => "Images",
        "discussions" => "Forums",
        "related_searches" => "Related"
      }.freeze

      CELLS = { ours: "shown, with your site in it", on: "shown", off: "not shown" }.freeze

      Feature = Data.define(:key, :label, :short, :seen, :share, :ours, :leader, :ownable)

      def tracking_phrases
        (questions + searches).map(&:text)
      end

      def tiles
        [
          Tile.new(label: "Searches read", value: number(result.readable.size), note: readable_note),
          Tile.new(label: "Featured snippets", value: number(shown("featured_snippet")), note: snippet_note),
          Tile.new(label: "Knowledge panels", value: number(shown("knowledge_graph")), note: "on your searches"),
          Tile.new(label: "Questions asked", value: number(result.questions.size), note: answered_note),
          Tile.new(label: "Local packs", value: number(shown("local_pack")), note: "maps above the results")
        ]
      end

      def features
        memo(:features) do
          result.counts.map do |key, label, seen, share|
            tally = holders(key).flatten.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }

            Feature.new(key: key, label: label, short: SHORT.fetch(key, label), seen: seen, share: share,
                        ours: holders(key).count { |domains| domains.any? { |domain| ours?(domain) } },
                        leader: tally.max_by { |_domain, count| count }&.first, ownable: tally.any?)
          end
        end
      end

      def shares?
        result.readable.size >= SHARE_FLOOR
      end

      def feature_cols
        [ "minmax(0, 1fr)", ("minmax(0, 1.2fr)" if shares?), "88px", "72px", "minmax(0, 1fr)" ].compact.join(" ")
      end

      def share_floor_note
        "Share of searches shows once #{SHARE_FLOOR} searches have been read. Out of fewer, every feature reads close to 100%."
      end

      def rows
        memo(:rows) { result.rows.select(&:readable?) }
      end

      def places?
        memo(:places) { rows.map(&:location).uniq.many? }
      end

      def snippets?
        features.any? { |feature| feature.key == "featured_snippet" }
      end

      def matrix_cols
        [ "minmax(160px, 1.4fr)", ("88px" if places?), *Array.new(features.size, "64px"),
          ("minmax(140px, 1fr)" if snippets?) ].compact.join(" ")
      end

      def cell(row, feature)
        return :off unless row.has?(feature.key)

        domains_for(row, feature.key).any? { |domain| ours?(domain) } ? :ours : :on
      end

      def cell_label(state)
        CELLS.fetch(state)
      end

      def questions
        memo(:questions) { result.questions.first(POOL_LIMIT) }
      end

      def questions_head
        questions.first(QUESTIONS_SHOWN)
      end

      def questions_rest
        questions.drop(QUESTIONS_SHOWN)
      end

      def repeats?
        questions.any? { |asked| asked.times > 1 }
      end

      def answered?
        questions.any? { |asked| asked.top.present? }
      end

      def question_cols
        [ "minmax(0, 1.6fr)", ("72px" if repeats?), ("minmax(0, 1fr)" if answered?), "72px" ].compact.join(" ")
      end

      def answered_by_note
        return "Answered by is the site Google shows as the answer most often." if answered?

        "None of these checks saved which site Google used as the answer, so that column is left out."
      end

      def questions_hint
        "#{pluralize(result.questions.size, "question")} across every search"
      end

      def searches
        memo(:searches) { result.searches.first(POOL_LIMIT) }
      end

      def searches_head
        searches.first(SEARCHES_SHOWN)
      end

      def searches_rest
        searches.drop(SEARCHES_SHOWN)
      end

      def searches_hint
        "#{pluralize(result.searches.size, "suggestion")} from Google"
      end

      def clean?
        result.clean?
      end

      def shown(key)
        result.counts.find { |candidate, _label, _seen, _share| candidate == key }&.third.to_i
      end

      def snippet_note
        held = result.snippets_held

        held.positive? ? "#{number(held)} of them yours" : "none of them yours"
      end

      def answered_note
        answered = result.questions.count { |asked| asked.answers.keys.any? { |domain| ours?(domain) } }

        "#{number(answered)} answered by you"
      end

      def readable_note
        return "every check saved" if clean?

        "#{number(result.blind.size)} with nothing saved"
      end

      def blind_note
        "Some older checks did not save the results page, so they have no features to show. " \
          "They are counted separately."
      end

      def ours?(domain)
        result.mine?(domain)
      end

      def unreadable?
        result.unreadable?
      end

      def csv_tables
        [ features_table, matrix_table, questions_table, related_table ]
      end

      def unreadable_empty
        { title: "No results pages saved in this range",
          hint: "#{pluralize(result.rows.size, "check")} ran in this range, and none of them saved the results page, " \
                "so there are no features to read. Try a longer date range, or run a check from Rankings.",
          action: { label: "Open Rankings", url: rankings_path, data: TOP, primary: false } }
      end

      private

      def features_table
        headers = [ "Feature", ("Share of searches" if shares?), "Searches", "Yours", "Held most by" ].compact

        CsvTable.new(key: "features", label: "Features on your results pages", headers: headers) do
          features.map do |feature|
            line = [ feature.label ]
            line << csv_percent(feature.share) if shares?
            line.push(feature.seen, (feature.ours if feature.ownable), feature.leader)
          end
        end
      end

      def matrix_table
        headers = [ "Search", ("Place" if places?), *features.map(&:label), ("Snippet held by" if snippets?) ].compact

        CsvTable.new(key: "matrix", label: "Search by search", headers: headers) do
          rows.map do |row|
            line = [ row.query ]
            line << row.place.label if places?
            line.concat(features.map { |feature| cell_label(cell(row, feature)).upcase_first })
            line << row.owner_of("featured_snippet") if snippets?
            line
          end
        end
      end

      def questions_table
        headers = [ "Question", ("Searches" if repeats?), ("Answered by" if answered?) ].compact

        CsvTable.new(key: "questions", label: "People also ask", headers: headers) do
          (questions_head + questions_rest).map do |asked|
            line = [ asked.text ]
            line << asked.times if repeats?
            line << asked.top if answered?
            line
          end
        end
      end

      def related_table
        CsvTable.new(key: "related", label: "Related searches", headers: [ "Related search", "Searches" ]) do
          (searches_head + searches_rest).map { |suggestion| [ suggestion.text, suggestion.times ] }
        end
      end

      def holders(key)
        memo(:"holders_#{key}") { rows.map { |row| domains_for(row, key) } }
      end

      def domains_for(row, key)
        return [] unless row.has?(key)
        return row.questions.map(&:domain).select { |value| value }.uniq if key == ASKED

        row.owners_of(key)
      end
    end
  end
end
