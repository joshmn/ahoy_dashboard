require "rails_helper"

RSpec.describe AhoyDashboard::FunnelPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }
  let(:funnel) { create(:dash_funnel, name: "Consults") }

  def step(position, name, visitors, rate, dropoff = nil, dropoff_rate = nil)
    AhoyDashboard::FunnelQuery::Step.new(
      position: position, name: name, visitors: visitors, conversion_rate: rate,
      dropoff: dropoff, dropoff_rate: dropoff_rate
    )
  end

  def result(steps)
    AhoyDashboard::FunnelQuery::Result.new(
      funnel: funnel,
      steps: steps,
      entered: steps.first.visitors,
      converted: steps.last.visitors,
      conversion_rate: steps.last.conversion_rate
    )
  end

  let(:walked) do
    [
      step(1, "/federal-prison-consultant", 40, 100.0),
      step(2, "consult_requested", 10, 25.0, 30, 75.0)
    ]
  end

  subject(:presenter) { described_class.new(query: query, funnel: funnel, result: result(walked)) }

  it "titles itself after the funnel" do
    expect(presenter.title).to eq("Consults")
  end

  it "names its own frames off the funnel's id" do
    expect(presenter.frame_id).to eq("report_funnel_#{funnel.id}")
    expect(described_class.details_frame_id(funnel)).to eq("report_details_funnel_#{funnel.id}")
    expect(described_class.modal_key(funnel)).to eq("funnel_#{funnel.id}")
  end

  it "answers with the details frame when it is the details view" do
    details = described_class.new(query: query, funnel: funnel, result: result(walked), details: true)

    expect(details).to be_details
    expect(details.frame_id).to eq("report_details_funnel_#{funnel.id}")
  end

  it "scales every bar against the first step" do
    expect(presenter.rows.map(&:share)).to eq([ 1.0, 0.25 ])
  end

  it "prints a rate that arrived as a percentage rather than a fraction" do
    expect(presenter.rows.first.values["conversion_rate"]).to eq("100.0%")
    expect(presenter.rows.last.values["conversion_rate"]).to eq("25.0%")
  end

  it "leaves the first step's loss blank" do
    expect(presenter.rows.first.values["dropoff"]).to eq("")
    expect(presenter.rows.first.values["dropoff_rate"]).to eq("")
    expect(presenter.rows.last.values["dropoff"]).to eq("30")
    expect(presenter.rows.last.values["dropoff_rate"]).to eq("75.0%")
  end

  it "says how many went the whole way" do
    expect(presenter.summary_line).to eq("10 of 40 went the whole way, 25.0%.")
  end

  it "carries the extra column only in the details view" do
    expect(presenter.columns.map { |column| column[:key] }).to eq(%w[visitors conversion_rate dropoff])

    details = described_class.new(query: query, funnel: funnel, result: result(walked), details: true)
    expect(details.columns.map { |column| column[:key] })
      .to eq(%w[visitors conversion_rate dropoff dropoff_rate])
  end

  describe "with nobody in it" do
    let(:nobody) { [ step(1, "one", 0, 0.0), step(2, "two", 0, 0.0, 0, 0.0) ] }

    subject(:presenter) { described_class.new(query: query, funnel: funnel, result: result(nobody)) }

    it "reads as empty" do
      expect(presenter).to be_empty
      expect(presenter.summary_line).to be_nil
    end

    it "draws no bar rather than dividing by nothing" do
      expect(presenter.rows.map(&:share)).to eq([ 0.0, 0.0 ])
    end
  end

  describe "paths" do
    it "carries the dashboard's own view onto both of them" do
      dated = AhoyDashboard::QueryForm.from_params({ period: "day" })
      presenter = described_class.new(query: dated, funnel: funnel, result: result(walked))

      expect(presenter.card_path).to eq("/telemetry/funnels/#{funnel.id}?period=day")
      expect(presenter.details_path).to include("view=details")
      expect(presenter.details_path).to include("period=day")
    end
  end

  describe "as json" do
    it "returns the steps, the counts and the rates" do
      payload = presenter.as_json

      expect(payload[:title]).to eq("Consults")
      expect(payload[:entered]).to eq(40)
      expect(payload[:converted]).to eq(10)
      expect(payload[:steps].map { |step| step[:name] })
        .to eq([ "/federal-prison-consultant", "consult_requested" ])
    end
  end
end
