require "rails_helper"

RSpec.describe AhoyDashboard::FilterEntries::Row do
  it "offers every operator a filter can match with, labelled the way the chips read" do
    row = described_class.new(key: "0", dimension: "country", operator: "is", values: [ "US" ], members: [])

    expect(row.operator_options).to eq([
      %w[is is], [ "is not", "is_not" ], %w[contains contains], [ "does not contain", "not_contains" ]
    ])
  end
end
