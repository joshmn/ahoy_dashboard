require "rails_helper"

RSpec.describe AhoyDashboard::DashboardHelper, type: :helper do
  describe "#dash_icon" do
    it "keeps decorative icons hidden from assistive technology" do
      svg = Nokogiri::HTML5.fragment(helper.dash_icon(:target)).at_css("svg|svg", "svg" => "http://www.w3.org/2000/svg")

      expect(svg.attributes.slice("aria-hidden", "focusable").transform_values(&:value))
        .to eq("aria-hidden" => "true", "focusable" => "false")
    end

    it "retains each caller's size and class" do
      svg = Nokogiri::HTML5.fragment(helper.dash_icon(:search, size: 20, class_name: "custom-icon"))
        .at_css("svg|svg", "svg" => "http://www.w3.org/2000/svg")

      expect(svg.attributes.slice("class", "width", "height").transform_values(&:value))
        .to eq("class" => "ic custom-icon", "width" => "20", "height" => "20")
    end
  end

  describe "#dash_row_label" do
    it "keeps a short label whole" do
      expect(helper.dash_row_label("/pricing", split: true)).not_to include("nm__tail")
    end

    it "keeps the last path segment whole when it is short enough" do
      html = helper.dash_row_label("/analysis/history/repeat-seizures.md", split: true)

      expect(html).to include(%(<span class="nm__tail">/repeat-seizures.md</span>))
      expect(html).to include(%(<span class="nm__head">/analysis/history</span>))
    end

    it "falls back to the last characters when the last segment is long" do
      label = "/takedowns/operation-offsides-2026-fifa-world-cup-streaming-domains.md"

      expect(helper.dash_row_label(label, split: true)).to include(%(<span class="nm__tail">#{label[-16..-1]}</span>))
    end
  end

  describe "#dash_flag" do
    it "draws a flag for a two letter code" do
      expect(helper.dash_flag("US")).to include("tm-flag--emoji")
    end

    it "draws the same flag for a full country name in any case" do
      expect(helper.dash_flag("United States")).to eq(helper.dash_flag("US"))
      expect(helper.dash_flag("germany")).to eq(helper.dash_flag("DE"))
    end

    it "draws nothing for a name it does not know" do
      expect(helper.dash_flag("Atlantis")).to be_nil
      expect(helper.dash_flag("")).to be_nil
    end
  end

  describe "#dash_row_chip" do
    it "renders no chip at all when a country has no flag" do
      expect(helper.dash_row_chip(:flag, "Atlantis")).to be_nil
      expect(helper.dash_row_chip(:flag, "France")).to include("flg")
    end

    it "gives a channel a glyph rather than a letter" do
      chip = helper.dash_row_chip(helper.dash_chip_kind("channel"), AhoyDashboard::Sql::DIRECT)

      expect(chip).to include("lc--glyph", "<svg")
      expect(chip).not_to include("lc__letter")
    end

    it "keeps favicons for sources" do
      expect(helper.dash_chip_kind("source")).to eq(:favicon)
    end
  end

  describe "#dash_row_name" do
    it "puts the chip off the raw label in front of the printed one" do
      name = Nokogiri::HTML5.fragment(helper.dash_row_name("France", chip: :flag, chip_label: "FR", class_name: "x"))
        .at_css("span.rn")

      expect(name["class"]).to eq("rn x")
      expect(name.at_css(".flg")).to be_present
      expect(name.at_css(".nm").text).to eq("France")
    end

    it "sets a path in mono and splits it" do
      name = Nokogiri::HTML5.fragment(helper.dash_row_name("/analysis/history/repeat-seizures.md", mono: true))
        .at_css("span.rn")

      expect(name["class"]).to eq("rn mono")
      expect(name.at_css(".nm__tail").text).to eq("/repeat-seizures.md")
    end
  end

  describe "#dash_chip_kind" do
    it "can leave the favicon off for a list that has no room for one" do
      expect(helper.dash_chip_kind("referrer", favicon: false)).to be_nil
      expect(helper.dash_chip_kind("country", favicon: false)).to eq(:flag)
    end
  end

  describe "#dash_markdown" do
    before { helper.extend(AhoyDashboard::ComponentsHelper) }

    it "puts each table in an answer inside its own scrolling region, numbered" do
      markup = Nokogiri::HTML5.fragment(helper.dash_markdown("| a | b |\n|---|---|\n| 1 | 2 |\n\ntext\n\n| c |\n|---|\n| 3 |"))
      regions = markup.css("[role=region]")

      expect(regions.map { |region| region["aria-label"] })
        .to eq([ "Table 1 in this answer, scrolls sideways", "Table 2 in this answer, scrolls sideways" ])
      expect(regions.map { |region| region["tabindex"] }).to all(eq("0"))
      expect(regions.first.css("td").map(&:text)).to eq(%w[1 2])
      expect(markup.at_css("p").text).to eq("text")
    end

    it "still strips raw html out of a table cell" do
      markup = helper.dash_markdown("| a |\n|---|\n| <script>1</script> |")

      expect(markup).not_to include("<script>")
      expect(markup).to include("&lt;script&gt;")
    end
  end
end
