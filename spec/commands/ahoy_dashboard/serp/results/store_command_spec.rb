require "rails_helper"

RSpec.describe AhoyDashboard::Serp::Results::StoreCommand do
  let(:run) { create(:dash_serp_run) }

  def combined(*organic)
    AhoyDashboard::Serp::Result.new(provider: :fake, query: "federal prison", organic: organic)
  end

  def organic(position, link, domain: nil)
    AhoyDashboard::Serp::Organic.new(position: position, link: link, domain: domain)
  end

  it "writes a row per result out of the stored pages" do
    create(:dash_serp_run_page, run: run)

    events = described_class.call(run: run)

    expect(events).to have_key(:ok)
    expect(run.results.pluck(:position, :domain)).to eq([ [ 1, "bop.gov" ], [ 2, "example.com" ] ])
    expect(run.results.pluck(:checked_at).uniq).to eq([ run.checked_at ])
  end

  it "replaces what was there rather than doubling it up" do
    create(:dash_serp_run_page, run: run)
    described_class.call(run: run)
    described_class.call(run: run)

    expect(run.results.count).to eq(2)
  end

  it "stamps every row and hands back what it wrote" do
    events = described_class.call(run: run, result: combined(organic(1, "https://a.example/x"), organic(2, "https://b.example/y")))

    expect(events[:ok].map(&:position)).to eq([ 1, 2 ])
    expect(run.results.where(created_at: nil).or(run.results.where(updated_at: nil))).to be_empty
    expect(run.results.ranked.pluck(:link, :page)).to eq([ [ "https://a.example/x", 1 ], [ "https://b.example/y", 1 ] ])
  end

  it "normalises the domain the same way saving one row at a time did" do
    described_class.call(run: run, result: combined(organic(1, "https://a.example/x", domain: "WWW.Shop.Example.")))

    expect(run.results.pluck(:domain)).to eq([ "shop.example" ])
  end

  it "keeps the rows already stored when a result cannot be saved" do
    create(:dash_serp_run_page, run: run)
    described_class.call(run: run)

    expect {
      described_class.call(run: run, result: combined(organic(1, "https://a.example/x"), organic(2, "")))
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(run.results.count).to eq(2)
  end

  it "refuses two results at the same position" do
    expect {
      described_class.call(run: run, result: combined(organic(1, "https://a.example/x"), organic(1, "https://b.example/y")))
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "says so when there is no readable page to read" do
    events = described_class.call(run: run)

    expect(events).to have_key(:nothing)
    expect(run.results).to be_empty
  end
end
