module AhoyDashboard
  module Seo
    class KeywordResearchPresenter < BasePresenter
      INTENTS = {
        "informational" => [ "I", :neutral ],
        "navigational" => [ "N", :neutral ],
        "commercial" => [ "C", :kind ],
        "transactional" => [ "T", :kind ]
      }.freeze

      EASY = "easy".freeze

      def initialize(only: nil, **options)
        super(**options)
        @only = only
      end

      def easy_only?
        @only == EASY && easy_wins.any?
      end

      def easy_path
        surface.path(picked.merge(only: EASY))
      end

      def all_path
        surface.path(picked)
      end

      def tracking_phrases
        (rows + questions.first(14)).map(&:query)
      end

      def tiles
        [
          Tile.new(label: "Ideas", value: number(result.rows.size), note: "for this phrase"),
          Tile.new(label: "Monthly searches", value: number(result.volume), note: "across every idea"),
          Tile.new(label: "Easy wins", value: number(easy_wins.size), note: "low difficulty, real volume",
                   url: (easy_path if easy_wins.any? && !easy_only?)),
          Tile.new(label: "Ranking", value: number(result.rows.count(&:tracked?)), note: "with a position on record"),
          Tile.new(label: "Never shown", value: number(result.untouched.size), note: "not one impression yet"),
          Tile.new(label: "Looked up", value: fetched_value, kind: :status)
        ]
      end

      def rows
        easy_only? ? easy_wins : result.rows
      end

      def questions
        result.questions
      end

      def clusters
        all_clusters.first(12)
      end

      def clusters?
        all_clusters.any? { |cluster| cluster.terms > 1 }
      end

      def cluster_share(cluster)
        top = memo(:top_cluster_volume) { all_clusters.map(&:volume).max.to_i }

        top.zero? ? 0 : cluster.volume.to_f / top
      end

      def easy?(row)
        memo(:easy) { easy_wins.map(&:query).to_set }.include?(row.query)
      end

      def volume_share(row)
        top = memo(:top_volume) { rows.map(&:volume).select { |value| value }.max.to_i }

        top.zero? || row.volume.nil? ? 0 : row.volume.to_f / top
      end

      def difficulty_tone(row)
        case row.band
        when "Easy" then :success
        when "Medium" then :warning
        else :danger
        end
      end

      def intent_letter(intent)
        INTENTS.dig(intent.to_s, 0) || intent.to_s.first.upcase
      end

      def intent_tone(intent)
        INTENTS.dig(intent.to_s, 1) || :neutral
      end

      def position_label(row)
        return row.position.to_s if row.tracked?

        "Shown" if row.seen?
      end

      def cpc_value(row)
        row.cpc ? money(row.cpc) : DASH
      end

      def volume_value(row)
        row.volume ? number(row.volume) : DASH
      end

      def fetched_value
        result.fetched_at ? when_label(result.fetched_at) : DASH
      end

      def seed
        result.seed
      end

      def location
        result.location
      end

      def language
        result.language
      end

      def place
        memo(:place) { ::AhoyDashboard::Serp::Location.parse(location) }
      end

      def place_country
        place.country_code.downcase
      end

      def place_city
        place.canonical_name.to_s
      end

      def picked
        { seed: seed, location: location, language: language }
      end

      def lookup
        ::AhoyDashboard::KeywordIdea::Lookup.new(**picked)
      end

      def lookups
        result.lookups
      end

      def country_options
        names = keyword_countries
        names = names.merge(place_country => place.country_name) unless names.key?(place_country)

        names.sort_by { |_code, name| name }.map { |code, name| [ name, code ] }
      end

      def enabled?
        ::AhoyDashboard::Keywords.enabled?
      end

      def available?
        ::AhoyDashboard::Keywords.available?
      end

      def setup_notice
        case refusal
        when :disabled then AhoyDashboard::SetupNotice.call(:keyword_research)
        when :unsupported then AhoyDashboard::SetupNotice.call(:keyword_provider, url: providers_path)
        when :unconfigured then AhoyDashboard::SetupNotice.call(:provider_credentials, url: providers_path)
        end
      end

      def refusal
        memo(:refusal) { ::AhoyDashboard::Keywords.refusal }
      end

      def invented?
        return result.sample? if any?

        ::AhoyDashboard::Keywords.sample?
      end

      def sample_detail
        return "Nothing looked up here is real until you choose a search provider." unless any?
        return "No search provider is set up yet, so every number on this page is made up." if ::AhoyDashboard::Keywords.sample?

        "These ideas were looked up before a real search provider was chosen. Look this phrase up again to replace them."
      end

      def refresh_path
        routes.seo_keyword_research_refreshes_path
      end

      def refresh_confirm
        "Look up #{lookup.label} again? This is a paid request."
      end

      def ideas_hint
        return "Ideas for a phrase show here once keyword research is ready." if setup_notice

        "Enter a phrase above to look up related searches with their volume and difficulty."
      end

      def provider
        ::AhoyDashboard::Keywords.provider
      end

      def lookup_path
        routes.seo_keyword_research_lookups_path
      end

      def lookup_reason
        refusal && ::AhoyDashboard::Keywords.refusal_message(refusal)
      end

      def lookup_fix
        refusal && refusal != :disabled ? { label: "Search provider", url: providers_path } : nil
      end

      def lookup_hint
        "Saved phrases open without paying again. Look up again buys fresh numbers."
      end

      def lookup_label
        seed.present? ? lookup.label : "Saved phrases"
      end

      def lookup_options
        lookups.map do |candidate|
          {
            label: candidate.label,
            url: surface.path(candidate.to_h),
            active: candidate == lookup
          }
        end
      end

      def difficulty_warning
        "Difficulty is the provider's number. Nothing here measures it."
      end

      def csv_tables
        [
          CsvTable.new(key: "ideas", label: "Keyword ideas",
                       headers: [ "Search", "Volume", "KD", "CPC", "Intent", "Your position" ]) do
            rows.map do |row|
              [ row.query, row.volume, row.difficulty, row.cpc&.to_f, row.intent.presence&.capitalize,
                csv_position(row) ]
            end
          end,
          CsvTable.new(key: "questions", label: "Questions", headers: [ "Question", "Volume" ]) do
            questions.first(14).map { |row| [ row.query, row.volume ] }
          end,
          CsvTable.new(key: "clusters", label: "Clusters", headers: [ "Cluster", "Ideas", "Volume" ]) do
            clusters.map { |cluster| [ cluster.name, cluster.terms, cluster.volume ] }
          end
        ]
      end

      def csv_position(row)
        return row.position if row.tracked?

        "Shown" if row.seen?
      end

      private

      def carried
        picked.merge(only: (EASY if easy_only?)).compact
      end

      def easy_wins
        memo(:easy_wins) { result.easy_wins }
      end

      def all_clusters
        memo(:clusters) { result.clusters }
      end

      def keyword_countries
        ::AhoyDashboard::Keywords.adapter_class.countries || ::AhoyDashboard::Serp::Location.country_names
      rescue ::AhoyDashboard::Serp::Error
        ::AhoyDashboard::Serp::Location.country_names
      end
    end
  end
end
