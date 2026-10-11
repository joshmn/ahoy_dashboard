require "rails_helper"

RSpec.describe AhoyDashboard::Seo::SerpFeatures do
  describe ".from" do
    it "answers three empty lists for nothing stored" do
      expect(described_class.from(nil)).to eq([ [], [], [] ])
      expect(described_class.from({})).to eq([ [], [], [] ])
    end

    it "answers three empty lists for a payload that is not a hash" do
      expect(described_class.from("plain text")).to eq([ [], [], [] ])
      expect(described_class.from([ 1, 2 ])).to eq([ [], [], [] ])
      expect(described_class.from(4)).to eq([ [], [], [] ])
    end

    it "reads a payload handed over as a json string" do
      features, _questions, searches = described_class.from({ "related_searches" => [ { "query" => "fsa credits" } ] }.to_json)

      expect(features.map(&:key)).to eq([ "related_searches" ])
      expect(searches).to eq([ "fsa credits" ])
    end

    context "with a dataforseo payload" do
      def payload(*items)
        { "tasks" => [ { "id" => "task-1", "result" => [ { "keyword" => "fci thomson", "items" => items } ] } ] }
      end

      def asked(*elements)
        { "type" => "people_also_ask", "rank_group" => 1, "items" => elements }
      end

      it "reads who answers a question out of the expanded element list" do
        _features, questions, _searches = described_class.from(payload(asked(
          { "type" => "people_also_ask_element", "title" => "Is FCI Thomson a max?", "seed_question" => nil,
            "expanded_element" => [
              { "type" => "people_also_ask_expanded_element", "url" => "https://www.bop.gov/locations/institutions/tom/",
                "domain" => "www.bop.gov", "title" => "FCI Thomson", "description" => "A medium security prison." }
            ] }
        )))

        question = sole_item(questions)
        expect(question.text).to eq("Is FCI Thomson a max?")
        expect(question.link).to eq("https://www.bop.gov/locations/institutions/tom/")
        expect(question.domain).to eq("bop.gov")
        expect(question.snippet).to eq("A medium security prison.")
      end

      it "keeps a question answered by an ai overview with nobody holding it" do
        _features, questions, _searches = described_class.from(payload(asked(
          { "type" => "people_also_ask_element", "title" => "How far is Thomson from Chicago?",
            "expanded_element" => [
              { "type" => "people_also_ask_ai_overview_expanded_element", "items" => [
                { "type" => "ai_overview_expanded_element", "text" => "About 150 miles.",
                  "references" => [ { "url" => "https://example.com/thomson", "domain" => "example.com" } ] }
              ] }
            ] }
        )))

        question = sole_item(questions)
        expect(question.text).to eq("How far is Thomson from Chicago?")
        expect(question.link).to be_nil
        expect(question.domain).to be_nil
      end

      it "keeps a question whose answer was never expanded" do
        _features, questions, _searches = described_class.from(payload(asked(
          { "type" => "people_also_ask_element", "title" => "Can you visit on weekends?", "expanded_element" => nil }
        )))

        expect(questions.map(&:text)).to eq([ "Can you visit on weekends?" ])
        expect(sole_item(questions).domain).to be_nil
      end

      it "lists the features on the page once each, with related searches as plain strings" do
        features, _questions, searches = described_class.from(payload(
          { "type" => "featured_snippet", "url" => "https://www.bop.gov/a", "domain" => "www.bop.gov", "title" => "Visiting" },
          { "type" => "organic", "url" => "https://example.com/b" },
          { "type" => "local_pack", "title" => "One", "domain" => "one.example" },
          { "type" => "local_pack", "title" => "Two", "domain" => "two.example" },
          asked,
          { "type" => "related_searches", "items" => [ "fci thomson visiting", "fci thomson address" ] }
        ))

        expect(features.map(&:key)).to eq(%w[featured_snippet local_pack people_also_ask related_searches])
        expect(features.first.owner).to eq("bop.gov")
        expect(searches).to eq([ "fci thomson visiting", "fci thomson address" ])
      end
    end

    context "with a named payload" do
      it "reads the link a question carries" do
        _features, questions, _searches = described_class.from(
          "related_questions" => [ { "question" => "What is FCI Thomson?", "link" => "https://www.bop.gov/tom",
                                     "snippet" => "A prison." } ]
        )

        expect(sole_item(questions).domain).to eq("bop.gov")
        expect(sole_item(questions).snippet).to eq("A prison.")
      end

      it "reads the link out of a source block" do
        _features, questions, _searches = described_class.from(
          "related_questions" => [ { "question" => "What is FCI Thomson?",
                                     "source" => { "link" => "https://example.com/tom" } } ]
        )

        expect(sole_item(questions).domain).to eq("example.com")
      end

      it "does not trip over a source written as a name or an entry that is not a record" do
        _features, questions, _searches = described_class.from(
          "related_questions" => [ { "question" => "What is FCI Thomson?", "source" => "Wikipedia" }, "stray" ]
        )

        expect(questions.map(&:text)).to eq([ "What is FCI Thomson?" ])
        expect(sole_item(questions).link).to be_nil
      end
    end

    context "with an ai overview" do
      def overview(payload)
        described_class.from(payload).first.find { |feature| feature.key == "ai_overview" }
      end

      it "reads a serpapi overview and every site it cites" do
        feature = overview("ai_overview" => { "text_blocks" => [ { "snippet" => "Yes." } ],
                                              "references" => [ { "link" => "https://www.bop.gov/a" },
                                                                { "link" => "https://example.com/b" } ] })

        expect(feature.label).to eq("AI overview")
        expect(feature.owners).to eq([ "bop.gov", "example.com" ])
      end

      it "reads a searchapi overview out of its reference links" do
        feature = overview("ai_overview" => { "markdown" => "Yes.", "reference_links" => [ { "link" => "https://example.com/b" } ] })

        expect(feature.owners).to eq([ "example.com" ])
      end

      it "reads the sample provider's overview" do
        feature = overview("overview" => { "body" => "A fake overview.", "cited" => [ { "slot" => 1, "url" => "https://example.com/b" } ] })

        expect(feature.owners).to eq([ "example.com" ])
      end

      it "reads a dataforseo overview and the sites it cites" do
        feature = overview("tasks" => [ { "result" => [ { "items" => [
          { "type" => "ai_overview", "items" => [ { "text" => "Yes.", "references" => [ { "url" => "https://example.com/b", "domain" => "example.com" } ] } ] }
        ] } ] } ])

        expect(feature.owners).to eq([ "example.com" ])
      end
    end

    context "with the other features on a named payload" do
      def features(payload)
        described_class.from(payload).first.index_by(&:key)
      end

      it "names who holds a local pack, top stories, videos, images and forums" do
        found = features(
          "local_results" => { "places" => [ { "title" => "One", "links" => { "website" => "https://one.example/" } },
                                             { "title" => "Two", "website" => "https://two.example/" } ] },
          "top_stories" => [ { "link" => "https://news.example/a", "source" => "News" } ],
          "inline_videos" => [ { "link" => "https://www.youtube.com/watch?v=1" } ],
          "inline_images" => [ { "link" => "https://www.google.com/imgres?x=1", "source" => "https://pics.example/p" } ],
          "discussions_and_forums" => [ { "link" => "https://www.reddit.com/r/prison/1" } ]
        )

        expect(found["local_pack"].owners).to eq([ "one.example", "two.example" ])
        expect(found["top_stories"].owners).to eq([ "news.example" ])
        expect(found["video"].owners).to eq([ "youtube.com" ])
        expect(found["images"].owners).to eq([ "pics.example" ])
        expect(found["discussions"].owners).to eq([ "reddit.com" ])
      end

      it "names nobody as the holder of related searches that link back to google" do
        found = features("related_searches" => [ { "query" => "fci thomson", "link" => "https://www.google.com/search?q=fci+thomson" } ])

        expect(found["related_searches"].owners).to be_empty
      end

      it "keeps every local pack entry on a dataforseo payload rather than only the first" do
        found = features("tasks" => [ { "result" => [ { "items" => [
          { "type" => "local_pack", "title" => "One", "domain" => "one.example" },
          { "type" => "local_pack", "title" => "Two", "url" => "https://two.example/" }
        ] } ] } ])

        expect(found["local_pack"].owners).to eq([ "one.example", "two.example" ])
      end
    end
  end
end
