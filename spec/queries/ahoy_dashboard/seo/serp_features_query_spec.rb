require "rails_helper"

RSpec.describe AhoyDashboard::Seo::SerpFeaturesQuery do
  let(:range) { 7.days.ago..Time.current }
  let(:keyword) { create(:dash_serp_keyword, query: "first step act cheat sheet") }

  def reading(response, page_number: 1, run: nil)
    run ||= create(:dash_serp_run, keyword: keyword, checked_at: 1.day.ago)
    create(:dash_serp_run_page, run: run, page_number: page_number, response: response)
    run
  end

  def typed(*items)
    { "tasks" => [ { "result" => [ { "items" => items } ] } ] }
  end

  it "reads a payload stored as a json string" do
    reading(typed({ "type" => "people_also_ask", "items" => [ { "title" => "Who qualifies?" } ] }).to_json)

    result = described_class.call(site: nil, range: range)

    expect(sole_item(result.rows).keys).to eq([ "people_also_ask" ])
    expect(result.questions.map(&:text)).to eq([ "Who qualifies?" ])
  end

  it "treats a string that is not json as nothing saved" do
    reading("not json at all")

    result = described_class.call(site: nil, range: range)

    expect(sole_item(result.rows)).not_to be_readable
    expect(result.questions).to be_empty
  end

  it "treats an array payload as nothing saved" do
    reading([ { "type" => "ai_overview" } ])

    expect(sole_item(described_class.call(site: nil, range: range).rows)).not_to be_readable
  end

  it "merges a paged run when one page is a string and the other a hash" do
    run = reading(typed({ "type" => "ai_overview" }).to_json)
    reading({ "related_searches" => [ "first step act" ] }, page_number: 2, run: run)

    expect { described_class.call(site: nil, range: range) }.not_to raise_error
  end

  it "survives items, results and tasks of the wrong shape" do
    reading({ "tasks" => "nope" })
    other = create(:dash_serp_keyword, query: "another search")
    create(:dash_serp_run_page,
           run: create(:dash_serp_run, keyword: other, checked_at: 1.day.ago),
           response: { "tasks" => [ { "result" => [ { "items" => [ nil, "text", 4, { "type" => "people_also_ask", "items" => "nope" },
                                                                   { "type" => "featured_snippet", "title" => [ "a" ], "snippet" => { "b" => 1 } },
                                                                   { "type" => "related_searches", "items" => [ nil, 7, { "title" => nil }, "kept" ] } ] } ] } ] })

    result = described_class.call(site: nil, range: range)

    expect(result.rows.size).to eq(2)
    expect(result.searches.map(&:text)).to eq([ "kept" ])
  end

  describe "whose spots are yours" do
    let(:payload) do
      { "answer_box" => { "title" => "Visiting", "link" => "https://help.example.com/visiting" },
        "local_results" => [ { "title" => "Office", "website" => "https://maps.example.com/office" } ] }
    end

    def presenter(site)
      result = described_class.call(site: site, range: range)

      AhoyDashboard::Seo::SerpFeaturesPresenter.new(
        query: double(to_query: {}), surface: AhoyDashboard::Seo::Surface.find("serp_features"), result: result, site: site
      )
    end

    it "counts a subdomain as yours when the site says to match subdomains" do
      reading(payload)
      site = create(:dash_serp_site, :subdomains, domain: "example.com")

      features = presenter(site).features.index_by(&:key)

      expect(presenter(site).result.snippets_held).to eq(1)
      expect(features["featured_snippet"].ours).to eq(1)
      expect(features["local_pack"].ours).to eq(1)
      expect(features["local_pack"].leader).to eq("maps.example.com")
    end

    it "leaves a subdomain out when the site does not match subdomains" do
      reading(payload)
      site = create(:dash_serp_site, domain: "example.com")

      expect(presenter(site).result.snippets_held).to eq(0)
      expect(presenter(site).features.sum(&:ours)).to eq(0)
    end

    it "shows the ai overview row with the sample provider's stored page" do
      reading({ "overview" => { "body" => "A fake overview.", "cited" => [ { "slot" => 1, "url" => "https://example.com/b" } ] } })
      site = create(:dash_serp_site, domain: "example.com")

      overview = presenter(site).features.find { |feature| feature.key == "ai_overview" }

      expect(overview.label).to eq("AI overview")
      expect(overview.ours).to eq(1)
    end
  end

  it "knows when no check in the range saved a results page" do
    reading(nil)

    result = described_class.call(site: nil, range: range)

    expect(result).to be_any
    expect(result).to be_unreadable
  end
end
