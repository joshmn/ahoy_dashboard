require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::Slice do
  let(:us) { { "dimension" => "country", "operator" => "is", "value" => "US" } }

  def snapshot(params)
    described_class.snapshot(AhoyDashboard::QueryForm.from_params(params))
  end

  it "saves the filters on screen as params, not labels" do
    expect(snapshot(filters: [ us ])).to eq("filters" => [ us ], "crawlers" => false, "internal" => false)
  end

  it "saves no filters as none, so a default segment made later cannot creep in" do
    expect(snapshot({})["filters"]).to eq("none")
  end

  it "saves the default segment that was on screen as filters of its own" do
    create(:dash_segment, applied_by_default: true)

    expect(snapshot({})["filters"]).to eq([ us ])
    expect(snapshot(filters: "none")["filters"]).to eq("none")
  end

  it "saves the crawler and internal toggles" do
    expect(snapshot(crawlers: "1", internal: "1")).to include("crawlers" => true, "internal" => true)
  end

  it "reads the dashboard's defaults when nothing was saved" do
    slice = described_class.from_context({})

    expect(slice).to be_default
    expect(slice.form_params).to eq({})
  end

  it "reads a saved empty list as no filters at all" do
    slice = described_class.from_context("slice" => { "filters" => "none" })

    expect(slice.form_params).to eq(filters: "none")
  end

  it "drops a saved filter whose dimension is gone and says which" do
    gone = { "dimension" => "gone", "operator" => "is", "value" => "x" }
    slice = described_class.from_context("slice" => { "filters" => [ us, gone ] })

    expect(slice.form_params[:filters]).to eq([ us ])
    expect(slice.dropped).to eq([ "gone is x" ])
  end

  it "lets the model replace the filters and keeps the toggles" do
    saved = described_class.from_context("slice" => { "filters" => [ us ], "crawlers" => true })
    asked = saved.with([ { "dimension" => "device", "value" => "mobile" } ])

    expect(asked.source).to eq(:asked)
    expect(asked.form_params).to eq(filters: [ { "dimension" => "device", "operator" => "is", "value" => "mobile" } ],
                                     crawlers: "1")
  end

  it "reads an empty list from the model as the whole site" do
    saved = described_class.from_context("slice" => { "filters" => [ us ] })

    expect(saved.with([]).form_params).to eq(filters: "none")
  end

  it "keeps the conversation's filters when the model passes none" do
    saved = described_class.from_context("slice" => { "filters" => [ us ] })

    expect(saved.with(nil)).to equal(saved)
  end

  describe "or groups" do
    let(:ca) { { "dimension" => "country", "operator" => "is", "value" => "CA" } }
    let(:grouped) { [ us.merge("group" => 0), ca.merge("group" => 0) ] }

    it "saves a group the screen was showing with its number" do
      expect(snapshot(filters: grouped)["filters"]).to eq(grouped)
    end

    it "reads a saved group back and keeps it together" do
      slice = described_class.from_context("slice" => { "filters" => grouped })
      form = AhoyDashboard::QueryForm.from_params(slice.form_params)

      expect(slice.dropped).to be_empty
      expect(form.filters.sentence).to eq("Country is US or CA")
    end

    it "still reads a saved list with no groups in it the way it always has" do
      slice = described_class.from_context("slice" => { "filters" => [ us, { "dimension" => "device", "operator" => "is", "value" => "mobile" } ] })

      expect(AhoyDashboard::QueryForm.from_params(slice.form_params).filters.groups.map(&:size)).to eq([ 1, 1 ])
    end

    it "takes a group from the model, as a number or as digits, and keeps it" do
      asked = described_class.new.with([ us.merge("group" => 3), ca.merge("group" => "3"),
                                         { "dimension" => "device", "value" => "mobile" } ])

      expect(asked.form_params[:filters]).to eq(
        [ us.merge("group" => 3), ca.merge("group" => 3),
          { "dimension" => "device", "operator" => "is", "value" => "mobile" } ]
      )
      expect(AhoyDashboard::QueryForm.from_params(asked.form_params).filters.sentence)
        .to eq("(Country is US or CA) and Device is mobile")
    end

    it "refuses a group that is not a whole number from 0 up" do
      expect { described_class.new.with([ us.merge("group" => -1) ]) }
        .to raise_error(described_class::InvalidFilters, /group -1/)
      expect { described_class.new.with([ us.merge("group" => "x") ]) }
        .to raise_error(described_class::InvalidFilters, /group "x"/)
      expect { described_class.new.with([ us.merge("group" => 1.5) ]) }
        .to raise_error(described_class::InvalidFilters, /group 1.5/)
    end

    it "drops a saved member with a bad group and says which" do
      slice = described_class.from_context("slice" => { "filters" => [ us, ca.merge("group" => "x") ] })

      expect(slice.form_params[:filters]).to eq([ us ])
      expect(slice.dropped).to eq([ "country is CA" ])
    end
  end

  describe "a dimension the host withheld from the assistant" do
    let(:city) { { "dimension" => "city", "operator" => "is", "value" => "Springfield" } }

    before { AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city]) }

    it "drops it from the saved slice without repeating its value" do
      slice = described_class.from_context("slice" => { "filters" => [ us, city ] })

      expect(slice.form_params[:filters]).to eq([ us ])
      expect(slice.dropped.join).to include("city")
      expect(slice.dropped.join).not_to include("Springfield")
    end

    it "refuses it from the model" do
      expect { described_class.new.with([ city ]) }
        .to raise_error(described_class::InvalidFilters, /city is kept out of the assistant/)
    end
  end

  it "refuses a filter it cannot read rather than reading what is left" do
    expect { described_class.new.with([ us, { "dimension" => "nonsense", "value" => "x" } ]) }
      .to raise_error(described_class::InvalidFilters, /no dimension called "nonsense"/)
    expect { described_class.new.with([ us.merge("operator" => "like") ]) }
      .to raise_error(described_class::InvalidFilters, /no operator called "like"/)
    expect { described_class.new.with([ us.merge("value" => "") ]) }
      .to raise_error(described_class::InvalidFilters, /has no value/)
    expect { described_class.new.with([ { "dimension" => "page_group", "value" => "x" } ]) }
      .to raise_error(described_class::InvalidFilters, /cannot be filtered on/)
  end
end
