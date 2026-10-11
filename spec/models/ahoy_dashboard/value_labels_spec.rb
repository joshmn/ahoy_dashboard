require "rails_helper"

RSpec.describe AhoyDashboard::ValueLabels do
  after { described_class.registry.delete("prop:thing") }

  it "answers nothing for a dimension nobody registered" do
    expect(described_class.for("prop:nobody", %w[1 2])).to eq({})
  end

  it "hands the whole page of values to the resolver at once" do
    seen = []
    described_class.register("prop:thing") do |values|
      seen << values
      values.map { |value| [ value, "Thing #{value}" ] }
    end

    expect(described_class.for("prop:thing", [ "1", "2", "2", nil ])).to eq(
      "1" => "Thing 1", "2" => "Thing 2"
    )
    expect(seen).to eq([ %w[1 2] ])
  end

  it "leaves a value the resolver did not answer for alone" do
    described_class.register("prop:thing") { |_values| [ [ "1", "Named" ] ] }

    expect(described_class.for("prop:thing", %w[1 2])).to eq("1" => "Named")
  end

  it "keeps drawing when a resolver blows up" do
    described_class.register("prop:thing") { |_values| raise "no" }

    expect(described_class.for("prop:thing", %w[1])).to eq({})
  end

  it "refuses to register without a lookup" do
    expect { described_class.register("prop:thing") }.to raise_error(ArgumentError)
  end
end
