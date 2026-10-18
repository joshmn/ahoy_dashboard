require "rails_helper"

RSpec.describe AhoyDashboard::SeoHelper, type: :helper do
  before do
    helper.extend(AhoyDashboard::ComponentsHelper)
    helper.extend(AhoyDashboard::DashboardHelper)
  end

  def html(markup)
    Nokogiri::HTML5.fragment(markup)
  end

  describe "#seo_plot" do
    it "draws one straight line through every value" do
      expect(helper.seo_plot([ 0, 50, 100 ], width: 100, height: 40, floor: 0, ceiling: 100))
        .to eq("M0.0 30.0 L50.0 20.0 L100.0 10.0")
    end

    it "lifts the pen over a missing value and starts again after it" do
      path = helper.seo_plot([ 0.5, nil, 0.25, 1.0 ], width: 90, height: 12, floor: 0, ceiling: 1, inset: 2, places: 1)

      expect(path).to eq("M0.0 6.0 M60.0 8.0 L90.0 2.0")
    end

    it "has nothing to draw below two values or with every value missing" do
      expect(helper.seo_plot([ 3 ])).to be_nil
      expect(helper.seo_plot([ nil, nil ], floor: 0, ceiling: 1)).to be_nil
    end
  end

  describe "#seo_stacks" do
    it "stacks each day's counts from the bottom of the plot" do
      day = Struct.new(:total, :counts) do
        def count(key)
          counts.fetch(key, 0)
        end
      end
      stacks = helper.seo_stacks([ day.new(4, { "top" => 3, "rest" => 1 }) ], keys: %w[top rest], width: 10, height: 8)

      expect(stacks.map { |stack| [ stack.x, stack.width, stack.segments.map(&:to_h) ] }).to eq([
        [ 1.4, 7.2, [ { key: "top", y: 2.0, height: 6.0 }, { key: "rest", y: 0.0, height: 2.0 } ] ]
      ])
    end
  end

  describe "#seo_figure" do
    it "draws the share meter beside its label" do
      figure = html(helper.seo_figure(0.25, "25%", wide: true)).at_css(".seo-figure")

      expect(figure["class"]).to eq("seo-figure seo-figure--start")
      expect(figure.at_css(".seo-meter.seo-meter--wide")["style"]).to eq("--w: 25.0%")
      expect(figure.at_css(".seo-figure__pct").text).to eq("25%")
    end
  end

  describe "#seo_overview_badge" do
    it "says whether the overview cited the site, and a dash when there was none" do
      cited = html(helper.seo_overview_badge("Cited")).at_css(".badge")
      shown = html(helper.seo_overview_badge("Shown", titled: false)).at_css(".badge")

      expect([ cited.text, cited["title"] ]).to eq([ "Cited", "The AI overview cited your site" ])
      expect([ shown.text, shown["title"] ]).to eq([ "Shown", nil ])
      expect(html(helper.seo_overview_badge(nil)).at_css(".nil")).to be_present
    end
  end
end
