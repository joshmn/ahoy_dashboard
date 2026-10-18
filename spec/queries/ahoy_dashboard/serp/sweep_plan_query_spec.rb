require "rails_helper"

RSpec.describe AhoyDashboard::Serp::SweepPlanQuery do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:site) { create(:dash_serp_site, :ours) }

  before do
    serp_enabled!
    allow(AhoyDashboard).to receive(:cache).and_return(cache)
  end

  def tracked(query)
    create(:dash_serp_keyword, :tracked, query: query, locations: [ "us" ], site: site)
  end

  def queue(keyword)
    cache.write(described_class.queued_key(keyword), Time.current.to_i)
  end

  it "leaves out what was just sent, asking the cache once for the whole list" do
    first, second, third = %w[one two three].map { |query| tracked(query) }
    queue(second)
    allow(cache).to receive(:read_multi).and_call_original
    allow(cache).to receive(:exist?).and_call_original

    plan = described_class.new

    expect(plan.keywords).to contain_exactly(first, third)
    expect(plan.refusal).to be_nil
    expect(cache).to have_received(:read_multi).once
    expect(cache).not_to have_received(:exist?)
  end

  it "says everything is queued when nothing is left to send" do
    queue(tracked("one"))

    expect(described_class.new.refusal).to eq(:queued)
  end

  it "says nothing is tracked when there is nothing to send at all" do
    expect(described_class.new.refusal).to eq(:nothing)
  end

  it "answers for one keyword on its own" do
    keyword = tracked("one")

    expect(described_class.new(keyword: keyword).refusal).to be_nil

    queue(keyword)

    expect(described_class.new(keyword: keyword).refusal).to eq(:queued)
  end

  it "finds the queued ones in a list without a read per keyword" do
    keywords = %w[one two three].map { |query| tracked(query) }
    queue(keywords.first)
    allow(cache).to receive(:read_multi).and_call_original

    expect(described_class.queued_ids(keywords)).to eq(Set[keywords.first.id])
    expect(described_class.queued_ids([])).to eq(Set.new)
    expect(cache).to have_received(:read_multi).once
  end
end
