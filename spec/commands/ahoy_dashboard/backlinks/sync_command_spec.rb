require "rails_helper"

RSpec.describe AhoyDashboard::Backlinks::SyncCommand do
  let(:now) { dash_time(2026, 8, 20, 9, 0) }
  let(:today) { now.to_date }
  let(:domains_endpoint) { AhoyDashboard::Serp::Adapters::DataForSeoAdapter::BACKLINK_ENDPOINT }
  let(:anchors_endpoint) { AhoyDashboard::Serp::Adapters::DataForSeoAdapter::ANCHOR_ENDPOINT }
  let!(:provider) do
    create(:dash_serp_provider, name: "dataforseo", monthly_cap_units: 10, units_spent: 3,
                                units_reset_on: now.to_date.beginning_of_month)
  end

  around { |example| travel_to(now) { example.run } }

  before do
    allow(AhoyDashboard::Backlinks).to receive_messages(enabled?: true, provider: :dataforseo, domain: "example.com")
    dataforseo_configured!
  end

  def json(body)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def stub_domains(*rows, total: nil)
    items = rows.map do |host, rank|
      { "domain" => host, "rank" => rank, "backlinks" => 3, "nofollow_backlinks" => 0 }
    end
    body = dataforseo_body(items: items)
    body["tasks"][0]["result"][0]["total_count"] = total || items.size

    stub_request(:post, domains_endpoint).to_return(json(body))
  end

  def stub_anchors(*texts)
    items = texts.map { |text| { "anchor" => text, "backlinks" => 4, "referring_domains" => 2 } }

    stub_request(:post, anchors_endpoint).to_return(json(dataforseo_body(items: items)))
  end

  def stored(domain, authority:, provider: "dataforseo")
    create(:dash_backlink_domain, domain: domain, authority: authority, links: 1,
           first_seen_on: today - 30, last_seen_on: today - 1,
           provider: provider)
  end

  it "counts both requests against the provider's ceiling" do
    stub_domains([ "a.com", 50 ])
    stub_anchors("this guide")

    events = described_class.call

    expect(events).to have_key(:ok)
    expect(provider.reload.spent_this_month).to eq(5)
    expect(provider.last_used_at).to eq(now)
  end

  it "sends nothing once the ceiling has no room for a sync" do
    provider.update!(units_spent: 9)
    request = stub_domains([ "a.com", 50 ])

    events = described_class.call

    expect(events).to have_key(:capped)
    expect(request).not_to have_been_requested
    expect(AhoyDashboard::BacklinkDomain.count).to be_zero
  end

  it "counts only the request that answered when the anchors fail" do
    stub_domains([ "a.com", 50 ])
    stub_request(:post, anchors_endpoint).to_return(status: 500, body: "")

    described_class.call

    expect(provider.reload.spent_this_month).to eq(4)
  end

  it "refuses to write sample data into the real tables" do
    allow(AhoyDashboard::Backlinks).to receive(:provider).and_return(:fake)

    events = described_class.call

    expect(events[:refused]).to eq("Backlinks would come from sample data. Choose a real search provider.")
    expect(AhoyDashboard::BacklinkDomain.count).to be_zero
    expect(AhoyDashboard::BacklinkSample.count).to be_zero
  end

  it "fails on a refused login rather than calling it a quota" do
    stub_request(:post, domains_endpoint)
      .to_return(status: 401, body: { "status_code" => 40_100, "status_message" => "Unauthorized." }.to_json)

    events = described_class.call

    expect(events[:failed]).to eq("Unauthorized.")
    expect(events).not_to have_key(:rate_limited)
    expect(provider.reload.last_error).to eq("Unauthorized.")
    expect(provider.spent_this_month).to eq(3)
  end

  it "keeps a referrer whose first seen date it cannot read, without the date" do
    body = dataforseo_body(items: [ { "domain" => "a.com", "rank" => 50, "backlinks" => 3, "nofollow_backlinks" => 0,
                                      "first_seen" => "not a date" } ])
    stub_request(:post, domains_endpoint).to_return(json(body))
    stub_anchors

    events = described_class.call

    expect(events[:ok].gained).to eq(1)
    expect(AhoyDashboard::BacklinkDomain.find_by!(domain: "a.com").first_seen_on).to eq(today)
  end

  it "refuses without a login" do
    dataforseo_configured!(login: nil)
    request = stub_domains([ "a.com", 50 ])

    events = described_class.call

    expect(events[:refused]).to eq("DataForSEO has no credentials set.")
    expect(request).not_to have_been_requested
  end

  it "says there is no domain to look up when the host is not set" do
    allow(AhoyDashboard::Backlinks).to receive(:domain).and_return(nil)

    events = described_class.call

    expect(events[:invalid]).to eq("no domain to look up")
  end

  it "marks a site lost when the whole profile came back without it" do
    stored("gone.com", authority: 5)
    stub_domains([ "a.com", 50 ])
    stub_anchors

    events = described_class.call

    expect(events[:ok].lost).to eq(1)
    expect(AhoyDashboard::BacklinkDomain.find_by(domain: "gone.com").lost_on).to eq(today)
  end

  it "only marks sites lost that would have made the cut when the profile was truncated" do
    stored("high.com", authority: 70)
    stored("low.com", authority: 10)
    stub_domains([ "a.com", 50 ], [ "b.com", 40 ], total: 900)
    stub_anchors

    events = described_class.call(limit: 2)

    expect(events[:ok].lost).to eq(1)
    expect(AhoyDashboard::BacklinkDomain.find_by(domain: "high.com").lost_on).to eq(today)
    expect(AhoyDashboard::BacklinkDomain.find_by(domain: "low.com").lost_on).to be_nil
  end

  it "adds sites it has not seen, refreshes the ones it knew and brings lost ones back" do
    known = stored("known.com", authority: 20)
    back = stored("back.com", authority: 30)
    back.update!(lost_on: today - 5)
    stub_domains([ "new.com", 50 ], [ "known.com", 60 ], [ "back.com", 70 ])
    stub_anchors

    events = described_class.call

    expect(events[:ok]).to have_attributes(domains: 3, gained: 1, lost: 0, returned: 1)
    expect(known.reload).to have_attributes(authority: 60, links: 3, first_seen_on: today - 30,
                                            last_seen_on: today, lost_on: nil)
    expect(back.reload).to have_attributes(authority: 70, first_seen_on: today - 30, last_seen_on: today, lost_on: nil)
    expect(AhoyDashboard::BacklinkDomain.find_by(domain: "new.com"))
      .to have_attributes(authority: 50, links: 3, first_seen_on: today, last_seen_on: today, provider: "dataforseo")
  end

  it "writes the whole profile in one statement however many sites came back" do
    stored("known.com", authority: 20)
    stub_domains(*(1..20).map { |n| [ "site#{n}.com", n ] }, [ "known.com", 60 ])
    stub_anchors
    writes = captured_sql(/\A\s*(INSERT|UPDATE)\s+(INTO\s+)?"ahoy_dashboard_backlink_domains"/i, cached: true) { described_class.call }

    expect(writes.size).to eq(2)
    expect(AhoyDashboard::BacklinkDomain.count).to eq(21)
  end

  it "drops anchor text the provider stopped returning" do
    create(:dash_backlink_anchor, text: "old anchor", links: 900, domains: 40, seen_on: today - 10)
    stub_domains([ "a.com", 50 ])
    stub_anchors("this guide")

    described_class.call

    expect(AhoyDashboard::BacklinkAnchor.pluck(:text)).to eq([ "this guide" ])
  end

  it "keeps the anchors it had when the anchor lookup fails" do
    create(:dash_backlink_anchor, text: "old anchor", links: 900, domains: 40, seen_on: today - 10)
    stub_domains([ "a.com", 50 ])
    stub_request(:post, anchors_endpoint).to_return(status: 500, body: "")

    described_class.call

    expect(AhoyDashboard::BacklinkAnchor.pluck(:text)).to eq([ "old anchor" ])
  end

  it "clears out sample rows on the first real sync instead of reporting them lost" do
    stored("reddit.com", authority: 90, provider: "fake")
    create(:dash_backlink_sample, on: today - 1, domains: 11, links: 40, provider: "fake")
    create(:dash_backlink_anchor, text: "read more", links: 90, domains: 4, seen_on: today - 1)
    stub_domains([ "a.com", 50 ])
    stub_anchors

    events = described_class.call

    expect(events[:ok].lost).to eq(0)
    expect(AhoyDashboard::BacklinkDomain.pluck(:domain, :provider)).to eq([ [ "a.com", "dataforseo" ] ])
    expect(AhoyDashboard::BacklinkSample.pluck(:provider)).to eq([ "dataforseo" ])
    expect(AhoyDashboard::BacklinkAnchor.count).to be_zero
  end
end
