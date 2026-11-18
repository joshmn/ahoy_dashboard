require "rails_helper"

RSpec.describe "Dashboard assistant prompt tools" do
  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  def converter!(token, landing:, at: 1.day.ago)
    visit = create(:ahoy_visit, visitor_token: token, started_at: at, landing_page: landing)
    create(:page_view_event, visit: visit, time: at, properties: { "path" => URI(landing).path })
    create(:ahoy_event, visit: visit, name: "signed_up", time: at + 1.minute, properties: {})
    visit
  end

  describe AhoyDashboard::Assistant::Tools::PromptEvidence do
    before { create(:dash_goal, event_name: "signed_up") }

    it "is only offered while AI visibility is on" do
      expect(described_class).to be_available

      ai_visibility_settings(enabled: false) { expect(described_class).not_to be_available }
    end

    it "works back from the converters and says how little there is to go on" do
      converter!("one", landing: "https://example.com/compare")

      answer = described_class.new.execute(days: 7)

      expect(answer[:anchor]).to eq("completing a goal")
      expect(answer[:converters]).to eq(1)
      expect(answer[:thin]).to include("only 1 visitors converted")
      expect(answer[:landed_on].map { |row| row[:page] }).to eq([ "/compare" ])
      expect(answer[:how_to_write_them]).to include("leave the brand terms out")
    end

    it "hands back the prompts already tracked and the ones nobody mentions the site in" do
      prompt = create(:dash_ai_prompt, text: "best self hosted analytics")
      create(:dash_ai_answer, prompt: prompt, mentioned: false)
      create(:dash_ai_source, answer: AhoyDashboard::AiVisibility::Answer.last, domain: "rival.example")

      tracking = described_class.new.execute(days: 7)[:tracking]

      expect(tracking[:prompts]).to eq([ "best self hosted analytics" ])
      expect(tracking[:not_mentioned_in]).to eq([ "best self hosted analytics" ])
      expect(tracking[:cited_instead]).to eq([ { domain: "rival.example", answers: 1 } ])
    end

    it "refuses a goal nobody set up and lists the ones there are" do
      answer = described_class.new.execute(goal: "nonsense")

      expect(answer[:error]).to include("nonsense")
      expect(answer[:goals]).to eq([ "signed_up" ])
    end

    it "finds a goal whatever case it is asked about in" do
      converter!("one", landing: "https://example.com/compare")

      expect(described_class.new.execute(goal: "SIGNED_UP", days: 7)[:goal]).to eq("signed_up")
    end

    it "leaves out what the site's owner keeps from the assistant" do
      AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[entry_page utm_term])
      converter!("one", landing: "https://example.com/compare")
      views = AhoyDashboard::Assistant::Views.new

      answer = described_class.new(views: views).execute(days: 7)

      expect(answer).not_to have_key(:landed_on)
      expect(answer).not_to have_key(:ai_assistants_send_people_to)
      expect(answer).not_to have_key(:paid_search_terms)
      expect(answer[:withheld]).to include("entry_page, utm_term")
      expect(views).not_to be_any
    end

    it "draws where converters landed" do
      converter!("one", landing: "https://example.com/compare")
      views = AhoyDashboard::Assistant::Views.new

      answer = described_class.new(views: views).execute(days: 7)

      expect(answer[:drawn]).to be(true)
      expect(views.to_a.first.rows).to eq([ { page: "/compare", first: 1, any: 1 } ])
    end
  end

  describe AhoyDashboard::Assistant::Tools::PromptEvidence, "with nothing to work back from" do
    it "says to set up a goal when there is no goal and no user_id" do
      allow(AhoyDashboard::Visitors::UserId).to receive(:visits?).and_return(false)

      answer = AhoyDashboard::Assistant::Tools::PromptEvidence.new.execute(days: 7)

      expect(answer[:error]).to include("nothing to work back from")
    end
  end

  describe AhoyDashboard::Assistant::Tools::ProposePrompts do
    def propose(*prompts, views: AhoyDashboard::Assistant::Views.new)
      described_class.new(views: views).execute(prompts: prompts.map { |text| { "text" => text, "because" => "/compare, 4 converters" } })
    end

    it "shows the suggestions and adds nothing" do
      views = AhoyDashboard::Assistant::Views.new

      answer = propose("what is a good self hosted analytics tool", views: views)

      expect(answer[:drawn]).to be(true)
      expect(answer[:shown]).to eq([ { text: "what is a good self hosted analytics tool", names_the_site: false } ])
      expect(views.to_a.first).to be_prompts
      expect(views.to_a.first.rows.first[:because]).to eq("/compare, 4 converters")
      expect(AhoyDashboard::AiVisibility::Prompt.count).to eq(0)
    end

    it "turns away what is tracked, repeated, blank or too long, and says why" do
      create(:dash_ai_prompt, text: "Best Analytics Tool")

      answer = propose("best analytics tool", "a fresh one", "A fresh one", "  ", "x" * 501)

      expect(answer[:shown].map { |row| row[:text] }).to eq([ "a fresh one" ])
      expect(answer[:turned_away].map { |row| row[:why] }).to eq(
        [ "it is already tracked", "it repeats another suggestion", "it is blank", "it is longer than 500 characters" ]
      )
    end

    it "flags a suggestion with the site's own name in it" do
      AhoyDashboard::Setting.write(AhoyDashboard::Seo::BrandTerms::KEY, [ "Acme" ])

      answer = propose("is acme any good")

      expect(answer[:shown].first[:names_the_site]).to be(true)
      expect(answer[:note]).to include("names_the_site")
    end

    it "stops at ten and at the room left in the set" do
      expect(propose(*Array.new(12) { |n| "question #{n}" })[:shown].size).to eq(10)

      create_list(:dash_ai_prompt, AhoyDashboard::AiVisibility::SettingsForm::MAX_PROMPTS - 2)

      answer = propose("one", "two", "three")

      expect(answer[:shown].size).to eq(2)
      expect(answer[:turned_away].first[:why]).to include("the set is full")
    end

    it "says what the suggestions would cost to ask" do
      create(:dash_ai_assistant, :keyed, name: "openai")
      create(:dash_ai_assistant, :keyed, name: "anthropic")

      cost = propose("one", "two")[:cost]

      expect(cost[:requests_per_run_each]).to eq(2)
      expect(cost[:how_often]).to eq("weekly")
      expect(cost[:requests_a_month_for_all_shown]).to eq(17)
    end
  end
end
