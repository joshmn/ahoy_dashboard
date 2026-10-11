require "rails_helper"
require "support/ahoy_dashboard/serp"

RSpec.describe AhoyDashboard::SerpRunPage do
  describe ".trim" do
    it "keeps the parts a later question could reach for" do
      kept = described_class.trim({ "organic_results" => [ 1 ], "ai_overview" => { "a" => 1 },
                                    "related_searches" => [], "ads" => [ 1, 2 ],
                                    "inline_images" => [ 1 ], "pagination" => {} },
                                  provider: :serpapi)

      expect(kept.keys).to contain_exactly("organic_results", "ai_overview", "related_searches",
                                           "inline_images")
    end

    it "answers with nothing for nothing" do
      expect(described_class.trim(nil, provider: :serpapi)).to eq({})
    end

    # The bug this covers: the slice above is a list of top level keys, and
    # dataforseo has none of them at the top level. Every reading through that
    # provider stored an empty response while raw_bytes went on recording the
    # real size, so the features were being paid for and thrown away.
    it "reaches into the nesting dataforseo answers with" do
      kept = described_class.trim({
        "status_code" => 20_000,
        "tasks" => [ { "id" => "t-1", "result" => [ { "keyword" => "k", "items" => [
          { "type" => "organic", "rank_absolute" => 1, "url" => "https://example.com/a" },
          { "type" => "people_also_ask", "items" => [ { "title" => "why?" } ] }
        ] } ] } ]
      }, provider: :dataforseo)

      expect(kept.dig("tasks", 0, "result", 0, "items").map { |item| item["type"] })
        .to eq(%w[organic people_also_ask])
    end

    it "leaves a dataforseo payload the adapter can still read back" do
      payload = { "tasks" => [ { "id" => "t-1", "result" => [ { "items" => [
        { "type" => "organic", "rank_absolute" => 1, "url" => "https://example.com/a", "title" => "A" }
      ] } ] } ] }

      kept = described_class.trim(payload, provider: :dataforseo)
      result = AhoyDashboard::Serp::Adapters::DataForSeoAdapter
        .new(login: "l", password: "p").parse_payload(kept, query: "k")

      expect(result.organic.map(&:link)).to eq([ "https://example.com/a" ])
    end

    it "answers with nothing when the nesting holds nothing" do
      expect(described_class.trim({ "status_code" => 40_400 }, provider: :dataforseo)).to eq({})
    end

    it "answers with nothing rather than raising for a provider nobody registered" do
      expect(described_class.trim({ "organic_results" => [ 1 ] }, provider: :nope)).to eq({})
    end
  end

  describe "#result" do
    it "reads a stored page back into the same shape the adapter answered with" do
      page = create(:dash_serp_run_page)
      result = page.result

      expect(result.provider).to eq(:fake)
      expect(result.organic.map(&:position)).to eq([ 1, 2 ])
      expect(result.rank_for("example.com").position).to eq(2)
      expect(result.ai_overview).to be_shown
      expect(result.cited?("example.com")).to be(true)
    end

    it "counts a stored second page on from where it started" do
      run = create(:dash_serp_run, requested_pages: 2)
      create(:dash_serp_run_page, run: run)
      page = create(:dash_serp_run_page, run: run, page_number: 2, start: 10)

      expect(page.result.organic.map(&:position)).to eq([ 11, 12 ])
    end

    it "answers nil rather than raising when nothing was stored" do
      expect(create(:dash_serp_run_page, response: nil).result).to be_nil
    end
  end

  it "runs the pages of a run together into one ranking" do
    run = create(:dash_serp_run, requested_pages: 2)
    create(:dash_serp_run_page, run: run)
    create(:dash_serp_run_page, run: run, page_number: 2, start: 10)

    expect(run.result.organic.map(&:position)).to eq([ 1, 2, 11, 12 ])
  end
end
