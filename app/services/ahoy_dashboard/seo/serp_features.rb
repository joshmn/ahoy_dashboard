module AhoyDashboard
  module Seo
    module SerpFeatures
      Feature = Data.define(:key, :label, :owner, :owners, :detail) do
        def initialize(key:, label:, detail:, owner: nil, owners: nil)
          held = Array(owners).compact.uniq
          held = [ owner, *held ].compact.uniq if owner

          super(key: key, label: label, owner: owner || held.first, owners: held.freeze, detail: detail)
        end
      end

      Question = Data.define(:text, :link, :domain, :snippet)

      Reading = Data.define(:features, :questions, :searches)

      CATALOGUE = {
        "featured_snippet" => "Featured snippet",
        "ai_overview" => "AI overview",
        "knowledge_graph" => "Knowledge panel",
        "people_also_ask" => "People also ask",
        "local_pack" => "Local pack",
        "top_stories" => "Top stories",
        "video" => "Video",
        "images" => "Images",
        "discussions" => "Forums and discussions",
        "related_searches" => "Related searches"
      }.freeze

      NAMED = {
        "answer_box" => [ "featured_snippet", "link" ],
        "ai_overview" => [ "ai_overview", nil ],
        "overview" => [ "ai_overview", nil ],
        "knowledge_graph" => [ "knowledge_graph", "website" ],
        "related_questions" => [ "people_also_ask", nil ],
        "local_results" => [ "local_pack", nil ],
        "top_stories" => [ "top_stories", nil ],
        "inline_videos" => [ "video", nil ],
        "inline_images" => [ "images", nil ],
        "discussions_and_forums" => [ "discussions", nil ],
        "related_searches" => [ "related_searches", nil ]
      }.freeze

      TYPED = {
        "featured_snippet" => "featured_snippet",
        "ai_overview" => "ai_overview",
        "knowledge_graph" => "knowledge_graph",
        "people_also_ask" => "people_also_ask",
        "local_pack" => "local_pack",
        "top_stories" => "top_stories",
        "video" => "video",
        "images" => "images",
        "discussions_and_forums" => "discussions",
        "related_searches" => "related_searches"
      }.freeze

      def self.label(key)
        CATALOGUE.fetch(key, key.to_s.humanize)
      end

      def self.from(payload)
        payload = readable(payload)
        return Reading.new(features: [], questions: [], searches: []) if payload.blank?

        typed?(payload) ? from_items(payload) : from_named(payload)
      end

      def self.readable(payload)
        payload = JSON.parse(payload) if payload.is_a?(String)

        payload.is_a?(Hash) ? payload : nil
      rescue JSON::ParserError
        nil
      end

      def self.typed?(payload)
        payload.key?("tasks")
      end

      def self.list(value)
        value.is_a?(Array) ? value : []
      end

      def self.text(value)
        value.is_a?(String) ? value.strip.presence : nil
      end

      def self.from_named(payload)
        features = NAMED.map do |key, (ours, owner_path)|
          value = payload[key]
          next if value.blank?

          Feature.new(key: ours, label: label(ours), owner: owner_from(value, owner_path),
                      owners: owners_in(value), detail: detail_for(value))
        end.select { |value| value }.uniq(&:key)

        Reading.new(features: features, questions: questions_from(Array(payload["related_questions"])),
                    searches: searches_from(payload["related_searches"]))
      end

      def self.from_items(payload)
        task = list(payload["tasks"]).first
        reading = list(task.is_a?(Hash) ? task["result"] : nil).first
        items = list(reading.is_a?(Hash) ? reading["items"] : nil).select { |item| item.is_a?(Hash) }

        features = items.select { |item| TYPED.key?(item["type"]) }.group_by { |item| TYPED[item["type"]] }
          .map do |ours, group|
            Feature.new(key: ours, label: label(ours), owner: Serp::Domain.host(group.first["url"] || group.first["domain"]),
                        owners: group.flat_map { |item| owners_in(item) }, detail: detail_for(group.first))
          end

        asked = items.find { |item| item["type"] == "people_also_ask" }
        related = items.find { |item| item["type"] == "related_searches" }

        Reading.new(features: features, questions: questions_from(asked_in(asked)),
                    searches: searches_from(related && related["items"]))
      end

      def self.asked_in(item)
        list(item.is_a?(Hash) ? item["items"] : nil).map do |element|
          next unless element.is_a?(Hash)

          answer = list(element["expanded_element"]).find do |expanded|
            expanded.is_a?(Hash) && expanded["url"].present?
          end || {}

          { "question" => element["title"], "link" => answer["url"], "snippet" => answer["description"] }
        end.select { |value| value }
      end

      def self.owner_from(value, path)
        return nil if path.nil? || !value.is_a?(Hash)

        Serp::Domain.host(value[path])
      end

      NESTED = %w[places items references reference_links cited sources].freeze

      NESTING = 4

      SEARCH_HOSTS = /(\A|\.)(google\.[a-z.]+|serpapi\.com|searchapi\.io)\z/

      def self.owners_in(value, depth: 0)
        return [] if depth > NESTING

        case value
        when Array then value.flat_map { |entry| owners_in(entry, depth: depth + 1) }.uniq
        when Hash
          nested = NESTED.flat_map { |key| value[key].is_a?(Array) ? owners_in(value[key], depth: depth + 1) : [] }

          [ owner_host(value), *nested ].compact.uniq
        else []
        end
      end

      def self.owner_host(entry)
        links = entry["links"].is_a?(Hash) ? entry["links"] : {}
        source = entry["source"] if entry["source"].is_a?(String) && entry["source"].include?("//")

        [ entry["website"], links["website"], entry["link"], entry["url"], entry["domain"], source ].each do |candidate|
          next unless candidate.is_a?(String)

          host = Serp::Domain.host(candidate)
          return host if host.present? && !host.match?(SEARCH_HOSTS)
        end

        nil
      end

      def self.detail_for(value)
        return "#{value.size} shown" if value.is_a?(Array)
        return nil unless value.is_a?(Hash)

        text(value["title"]) || text(value["snippet"])&.truncate(90)
      end

      def self.questions_from(entries)
        list(entries).map do |entry|
          next unless entry.is_a?(Hash)

          asked = text(entry["question"]) || text(entry["title"])
          next if asked.nil?

          source = entry["source"].is_a?(Hash) ? entry["source"] : {}
          link = text(entry["link"]) || text(source["link"]) || text(entry["url"])

          Question.new(text: asked, link: link, domain: Serp::Domain.host(link),
                       snippet: (text(entry["snippet"]) || text(entry["description"]))&.truncate(160))
        end.select { |value| value }
      end

      def self.searches_from(entries)
        list(entries).map do |entry|
          text(entry.is_a?(Hash) ? (entry["query"] || entry["title"] || entry["text"]) : entry)
        end.select { |value| value }.uniq
      end
    end
  end
end
