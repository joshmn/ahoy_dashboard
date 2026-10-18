require "rails_helper"

RSpec.describe "ahoy_dashboard/reports/_breakdown_picker", type: :view do
  let(:report) { AhoyDashboard::Report.find("pages") }
  let(:form) { AhoyDashboard::QueryForm.from_params({ period: "7d" }) }

  before do
    query = form

    view.define_singleton_method(:query) { query }
  end

  def picker(tab)
    presenter = AhoyDashboard::ReportPresenter.new(
      query: form, report: report, tab: tab,
      result: AhoyDashboard::BreakdownQuery::Result.new(rows: [], total: 0, more: false)
    )

    render partial: "ahoy_dashboard/reports/breakdown_picker", locals: { report: report, presenter: presenter }

    Nokogiri::HTML5.fragment(rendered)
  end

  def labels(tab)
    picker(tab).css("[data-dash--menu-target=panel] a").map { |item| item.text.strip }
  end

  def tab(key, breakdown = nil)
    report.tab(key).resolve(breakdown: breakdown)
  end

  it "offers a path and the rails controller on top pages" do
    expect(labels(tab("pages"))).to eq([ "Path", "Grouped", "Rails controller" ])
  end

  it "offers a path, the full url and the hostname on entry pages" do
    expect(labels(tab("entry_pages"))).to eq([ "Path", "URL", "Hostname" ])
  end

  it "renders nothing at all for a tab that offers no choice" do
    expect(picker(tab("exit_pages")).css("*")).to be_empty
    expect(picker(AhoyDashboard::Report.find("sources").tab("channels")).css("*")).to be_empty
  end

  it "ticks the option the card is grouping by" do
    active = picker(tab("entry_pages", "url")).css("a[aria-current=true]")

    expect(active.map { |item| item.text.strip }).to eq([ "URL" ])
    expect(active.first["aria-current"]).to eq("true")
    expect(active.first.css("svg|svg", "svg" => "http://www.w3.org/2000/svg")).not_to be_empty
  end

  it "ticks the option the card opens on when nobody has picked one" do
    expect(picker(tab("entry_pages")).at_css("a[aria-current=true]").text.strip).to eq("Path")
  end

  it "ticks the option the card fell back to on a value nobody registered" do
    expect(picker(tab("entry_pages", "banana")).at_css("a[aria-current=true]").text.strip)
      .to eq("Path")
  end

  it "names the showing option on the button, with a label that says what it is" do
    button = picker(tab("entry_pages", "host")).at_css("button")

    expect(button.text.strip).to eq("Hostname")
    expect(button["aria-label"]).to eq("Break down by: Hostname")
    expect(button["aria-expanded"]).to eq("false")
    expect(button["aria-controls"]).to eq("tm-card-pages-breakdown")
  end

  it "labels the panel with the button that opens it" do
    panel = picker(tab("pages")).at_css("[data-dash--menu-target=panel]")

    expect(panel["id"]).to eq("tm-card-pages-breakdown")
    expect(panel["aria-labelledby"]).to eq("tm-card-pages-breakdown-button")
    expect(panel.text).to include("Break down by")
  end

  it "renders every option as a link" do
    expect(picker(tab("pages")).css("[data-dash--menu-target=panel] a").size).to eq(3)
  end

  it "asks for the same tab, the new breakdown, and the range the dashboard is on" do
    hrefs = picker(tab("pages")).css("[data-dash--menu-target=panel] a").map { |item| item["href"] }

    expect(hrefs).to all(include("tab=pages"))
    expect(hrefs).to all(include("period=7d"))
    expect(hrefs.first).to include("breakdown=path")
    expect(hrefs.last).to include("breakdown=controller")
  end

  it "hangs the menu behaviour off the shared controller" do
    menu = picker(tab("pages")).at_css("[data-controller='dash--menu']")

    expect(menu["data-controller"]).to eq("dash--menu")
    expect(menu["data-tm-picker"]).to eq("breakdown")
    expect(menu.at_css("button")["data-action"]).to eq("dash--menu#toggle")
  end
end
