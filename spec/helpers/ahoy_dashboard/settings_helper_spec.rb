require "rails_helper"

RSpec.describe AhoyDashboard::SettingsHelper, type: :helper do
  before do
    helper.extend(AhoyDashboard::ComponentsHelper)
    helper.extend(AhoyDashboard::DashboardHelper)
  end

  def html(markup)
    Nokogiri::HTML5.fragment(markup)
  end

  describe "#dash_delete_confirm" do
    it "asks in the row, names the record, and deletes or goes back" do
      confirm = helper.dash_delete_confirm("Signup <b>", "Past conversions stay.", url: "/goals/1", cancel: "/goals", span: 7)
      row = html("<table><tbody>#{confirm}</tbody></table>").at_css("tr#confirm")

      expect(row.at_css("td")["colspan"]).to eq("7")
      expect(row.at_css("p").text).to eq("Delete Signup <b>? Past conversions stay.")
      expect(row.at_css("p b").text).to eq("Signup <b>")
      expect(row.at_css("form")["action"]).to eq("/goals/1")
      expect(row.at_css("form input[name=_method]")["value"]).to eq("delete")
      expect(row.at_css("form button").text).to eq("Delete")
      expect(row.at_css("a[autofocus]")["href"]).to eq("/goals")
    end
  end

  describe "#dash_move_buttons" do
    def buttons(index:, count:)
      html(helper.dash_move_buttons("/goals/1", name: "Signup", param: :goal, index: index, count: count))
    end

    it "nudges the record up or down under its own param" do
      forms = buttons(index: 1, count: 3).css("form")

      expect(forms.map { |form| form["action"] }).to eq([ "/goals/1", "/goals/1" ])
      expect(forms.map { |form| form.at_css("input[name=_method]")["value"] }).to eq(%w[patch patch])
      expect(forms.map { |form| form.at_css("input[name='goal[nudge]']")["value"] }).to eq(%w[up down])
      expect(forms.map { |form| form.at_css("button")["aria-label"] })
        .to eq([ "Move Signup up the list", "Move Signup down the list" ])
      expect(forms.map { |form| form.at_css("button")["disabled"] }).to eq([ nil, nil ])
    end

    it "switches off up on the first row and down on the last" do
      expect(buttons(index: 0, count: 3).css("button").map { |button| button["disabled"] }).to eq([ "disabled", nil ])
      expect(buttons(index: 2, count: 3).css("button").map { |button| button["disabled"] }).to eq([ nil, "disabled" ])
      expect(buttons(index: 0, count: 1).css("button").map { |button| button["disabled"] }).to eq(%w[disabled disabled])
    end

    it "keeps a space between the two buttons, the way the rows always had one" do
      expect(helper.dash_move_buttons("/goals/1", name: "Signup", param: :goal, index: 0, count: 2)).to include("</form> <form")
    end
  end

  describe "#dash_edit_button and #dash_delete_button" do
    it "links to the edit page and to the in-row confirmation" do
      edit = html(helper.dash_edit_button("Signup", "/goals/1/edit")).at_css("a")
      delete = html(helper.dash_delete_button("Signup", "/goals?confirm=1")).at_css("a")

      expect(edit["href"]).to eq("/goals/1/edit")
      expect(edit["aria-label"]).to eq("Edit Signup")
      expect(edit["title"]).to eq("Edit")
      expect(delete["href"]).to eq("/goals?confirm=1")
      expect(delete["aria-label"]).to eq("Delete Signup")
      expect(delete["title"]).to eq("Delete")
      expect(delete["class"]).to include("btn-icon-danger")
    end

    it "passes anything else through, like a frame to break out of" do
      edit = html(helper.dash_edit_button("Ours", "/sites/1/edit", data: { tm_frame: "_top" })).at_css("a")

      expect(edit["data-tm-frame"]).to eq("_top")
    end
  end

  describe "#dash_keyword_form_data" do
    let(:plan) do
      instance_double(AhoyDashboard::Settings::KeywordPlanPresenter, costs: { 1 => 1 }, durations: { "daily" => 86_400 },
                                                                     capped?: true, remaining: 40)
    end

    it "wires the keyword form controller, and leaves the limit off unless one is given" do
      data = helper.dash_keyword_form_data(plan)

      expect(data[:controller]).to eq("dash--keyword-form")
      expect(data[:"dash--keyword-form-costs-value"]).to eq({ 1 => 1 }.to_json)
      expect(data[:"dash--keyword-form-remaining-value"]).to eq(40)
      expect(data[:"dash--keyword-form-limit-value"]).to be_nil
      expect(helper.dash_keyword_form_data(plan, limit: 100)[:"dash--keyword-form-limit-value"]).to eq(100)
    end

    it "sends no remaining count when there is no cap" do
      allow(plan).to receive(:capped?).and_return(false)

      expect(helper.dash_keyword_form_data(plan)[:"dash--keyword-form-remaining-value"]).to be_nil
    end
  end
end
