require "rails_helper"

RSpec.describe AhoyDashboard::ReportPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }
  let(:report) { AhoyDashboard::Report.find("behaviours") }
  let(:properties_tab) { report.tab("properties") }
  let(:goals_tab) { report.tab("goals") }

  def result(rows: [])
    AhoyDashboard::BreakdownQuery::Result.new(rows: rows, total: rows.size, more: false)
  end

  def presenter(tab:, dimension: nil, property_keys: nil, **options)
    described_class.new(
      query: query, report: report, tab: tab, result: result,
      dimension: dimension, property_keys: property_keys, **options
    )
  end

  def property_dimension(name)
    AhoyDashboard::Dimension.find("prop:#{name}")
  end

  describe "the property picker options" do
    subject(:options) do
      presenter(tab: properties_tab, dimension: property_dimension("query"),
                property_keys: %w[facility_id query term]).property_options
    end

    it "offers every key it was handed, in the order they arrived" do
      expect(options.map(&:label)).to eq(%w[facility_id query term])
    end

    it "marks the one the card is showing and nothing else" do
      expect(options.select(&:active?).map(&:value)).to eq([ "query" ])
    end

    it "carries the whole current view plus the tab and the property in each path" do
      path = options.find { |option| option.value == "term" }.path

      expect(path).to include("tab=properties")
      expect(path).to include("property=term")
    end

    it "is empty on a tab that is not about properties" do
      expect(presenter(tab: goals_tab, property_keys: %w[facility_id]).property_options).to eq([])
    end

    it "is empty when nothing was handed to it" do
      expect(presenter(tab: properties_tab, dimension: property_dimension("query")).property_options)
        .to eq([])
    end
  end

  describe "the links the card builds" do
    it "names the property on the details link, so the modal groups by the same key" do
      showing = presenter(tab: properties_tab, dimension: property_dimension("term"))

      expect(showing.details_path).to include("property=term")
      expect(showing.details_params[:property]).to eq("term")
    end

    it "names the property on the export link too" do
      showing = presenter(tab: properties_tab, dimension: property_dimension("term"))

      expect(showing.export_path).to include("property=term")
    end

    it "names no property when the range has none to show" do
      empty = presenter(tab: properties_tab, dimension: property_dimension("property"), property_keys: [])

      expect(empty.no_properties?).to be(true)
      expect(empty.details_path).not_to include("property=")
      expect(empty.property_options).to eq([])
    end

    it "keeps the property off the links of a tab that has none" do
      expect(presenter(tab: goals_tab).details_path).not_to include("property=")
    end

    it "keeps the property off the tab links, so switching tabs is a clean switch" do
      showing = presenter(tab: properties_tab, dimension: property_dimension("term"))

      expect(showing.tabs.map(&:path)).to all(satisfy { |path| !path.include?("property=") })
    end
  end

  describe "what the card and the dialog print" do
    let(:locations) { AhoyDashboard::Report.find("locations") }

    def built(total: 0, rows: [], more: false, page: 1, per_page: nil, tab: locations.tab("countries"))
      described_class.new(
        query: query, report: locations, tab: tab, page: page, per_page: per_page, details: true,
        result: AhoyDashboard::BreakdownQuery::Result.new(rows: rows, total: total, more: more)
      )
    end

    it "names the dimension in the singular over the rows" do
      expect(built.label_heading).to eq("Country")
      expect(built(tab: locations.tab("cities")).label_heading).to eq("City")
    end

    it "prints a sliver of the total as under a tenth of a percent rather than zero" do
      row = double(metrics: { "visitors" => 3 })

      expect(built(total: 10_000).percent_of_total(row)).to eq("<0.1%")
      expect(built(total: 1_000).percent_of_total(row)).to eq("0.3%")
    end

    it "says top when there is another page and a count only when the count is the whole list" do
      rows = Array.new(3) { double }

      expect(built(rows: rows, more: true).count_label).to eq("Top 3")
      expect(built(rows: rows).count_label).to eq("3 values")
      expect(built(rows: rows, more: true, page: 2, per_page: 100).count_label).to eq("Rows 101 to 103")
      expect(built(rows: rows, page: 2, per_page: 100).count_label).to eq("Rows 101 to 103 of 103")
    end

    describe "a row toggling its own filter" do
      let(:us) { AhoyDashboard::BreakdownQuery::Row.new(label: "US", value: "US", metrics: { "visitors" => 1 }) }

      def toggled(filters)
        query = AhoyDashboard::QueryForm.from_params({ filters: filters })
        described_class.new(query: query, report: locations, tab: locations.tab("countries"),
                            result: AhoyDashboard::BreakdownQuery::Result.new(rows: [ us ], total: 1, more: false))
      end

      it "takes off the filter it put on" do
        showing = toggled([ { dimension: "country", operator: "is", value: "US" } ])

        expect(showing.rows.first).to be_filtered
        expect(showing.toggle_params(us)[:filters]).to be_nil
      end

      it "leaves an or group naming the row alone" do
        grouped = [ { dimension: "country", operator: "is", value: "US", group: "0" },
                    { dimension: "country", operator: "is", value: "CA", group: "0" } ]
        showing = toggled(grouped)

        expect(showing.rows.first).not_to be_filtered
        expect(showing.toggle_params(us)[:filters]).to include(
          { "dimension" => "country", "operator" => "is", "value" => "US", "group" => 0 },
          { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => 0 }
        )
      end
    end
  end
end
