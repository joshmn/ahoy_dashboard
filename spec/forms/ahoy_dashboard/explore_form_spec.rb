# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::ExploreForm do
  it "reads a string-keyed URL into its grouping and pagination" do
    form = described_class.from_params({ "dimension" => "country", "page" => "2", "q" => " Canada " })

    expect(form.to_query).to eq(dimension: "country", page: 2, q: "Canada")
  end

  it "accepts controller parameters at its input boundary" do
    form = described_class.from_params(ActionController::Parameters.new(dimension: "country", page: "2"))

    expect(form.to_query).to eq(dimension: "country", page: 2)
  end

  it "keeps malformed input on the default grouping" do
    expect(described_class.from_params("invalid").dimension.key).to eq("page")
  end
end
