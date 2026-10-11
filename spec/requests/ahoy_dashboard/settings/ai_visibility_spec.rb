require "rails_helper"
require "support/ahoy_dashboard/ai_visibility_settings"

RSpec.describe "Dashboard AI visibility settings", type: :request do
  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  def save(prompts:, frequency: "weekly", monthly_cap: "200", confirm: nil)
    patch "/telemetry/settings/ai_visibility",
      params: { ai_visibility: { prompts: prompts, frequency: frequency, monthly_cap: monthly_cap, confirm: confirm }.compact }
  end

  def texts
    AhoyDashboard::AiVisibility::Prompt.ordered.pluck(:text)
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/ai_visibility/edit"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin, and saves nothing" do
      sign_in create(:user)

      save(prompts: "a question")

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::AiVisibility::Prompt.count).to be_zero
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "lists all four assistants with whether each is asked, its models and its key state" do
      create(:dash_ai_assistant, :keyed, name: "openai", models: %w[gpt-5 gpt-4.1])
      create(:dash_ai_assistant, :keyed, name: "perplexity", enabled: false)

      get "/telemetry/settings/ai_visibility/edit"

      document = Nokogiri::HTML5(response.body)
      rows = document.css("[aria-label='Assistants'] table tbody tr").map { |row| row.text.squish }
      expect(rows.size).to eq(4)
      expect(rows.find { |row| row.start_with?("ChatGPT") }).to include("On", "gpt-5, gpt-4.1", "Stored here")
      expect(rows.find { |row| row.start_with?("Claude") }).to include("On", "claude-opus-5", "Missing")
      expect(rows.find { |row| row.start_with?("Gemini") }).to include("Missing")
      expect(rows.find { |row| row.start_with?("Perplexity") }).to include("Off", "Stored here")
      expect(document.at_css("a[href='/telemetry/settings/ai_visibility_assistants/perplexity/edit']")).to be_present
    end

    it "says when AI visibility is off" do
      ai_visibility_settings(enabled: false) do
        get "/telemetry/settings/ai_visibility/edit"
      end

      expect(response.body).to include("AI visibility is off. Turn it on under Settings, Features.")
    end

    it "shows the stored prompts, the schedule, the cap, what was used and the size of a run" do
      create(:dash_ai_assistant, :keyed, models: %w[gpt-5 gpt-4.1])
      create(:dash_ai_assistant, :keyed, name: "gemini", enabled: false)
      create(:dash_ai_prompt, text: "first question", position: 0)
      create(:dash_ai_prompt, text: "second question", position: 1)
      create(:dash_ai_answer)
      AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::FREQUENCY_KEY, "daily")
      AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 50)

      get "/telemetry/settings/ai_visibility/edit"

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("textarea#ai_visibility_prompts").text.strip).to start_with("first question\nsecond question")
      expect(document.at_css("input[name='ai_visibility[frequency]'][value='daily']")["checked"]).to be_present
      expect(document.at_css("input#ai_visibility_monthly_cap")["value"]).to eq("50")
      expect(document.at_css("#ai_visibility_monthly_cap_hint").text.squish)
        .to include("Used this month: 1.", "A run is 6 requests: 3 prompts to 2 models.")
    end

    it "adds prompts in line order and saves the schedule and cap" do
      save(prompts: "  first   question \n\nsecond question\n", frequency: "monthly", monthly_cap: "0")

      expect(response).to redirect_to("/telemetry/settings/ai_visibility/edit")
      expect(texts).to eq([ "first question", "second question" ])
      expect(AhoyDashboard::AiVisibility.frequency).to eq("monthly")
      expect(AhoyDashboard::AiVisibility.monthly_cap).to eq(0)
      expect(AhoyDashboard::AiVisibility).not_to be_capped
    end

    it "collapses duplicate lines, ignoring case and spacing" do
      save(prompts: "Best consultant\nbest  consultant\nBEST CONSULTANT\nother")

      expect(texts).to eq([ "Best consultant", "other" ])
    end

    it "reorders without touching the rows or their answers" do
      first = create(:dash_ai_prompt, text: "first", position: 0)
      second = create(:dash_ai_prompt, text: "second", position: 1)
      answer = create(:dash_ai_answer, prompt: first)

      save(prompts: "second\nfirst")

      expect(AhoyDashboard::AiVisibility::Prompt.ordered.pluck(:id)).to eq([ second.id, first.id ])
      expect(AhoyDashboard::AiVisibility::Answer.exists?(answer.id)).to be(true)
    end

    it "removes a prompt with no answers without asking" do
      create(:dash_ai_prompt, text: "keep", position: 0)
      create(:dash_ai_prompt, text: "drop", position: 1)

      save(prompts: "keep")

      expect(response).to redirect_to("/telemetry/settings/ai_visibility/edit")
      expect(texts).to eq([ "keep" ])
    end

    it "asks before removing a prompt that has answers, and changes nothing until confirmed" do
      create(:dash_ai_prompt, text: "keep", position: 0)
      doomed = create(:dash_ai_prompt, text: "drop this one", position: 1)
      create_list(:dash_ai_answer, 2, prompt: doomed)

      save(prompts: "keep\nnew one", frequency: "daily")

      expect(response).to have_http_status(:ok)
      confirm = Nokogiri::HTML5(response.body).at_css("#confirm")
      expect(confirm.text.squish).to include("Nothing is saved yet.", "drop this one (2 answers)")
      expect(confirm.at_css("form input[name='ai_visibility[confirm]'][value='1']")).to be_present
      expect(confirm.at_css("form input[name='ai_visibility[prompts]']")["value"]).to eq("keep\nnew one")
      expect(texts).to eq([ "keep", "drop this one" ])
      expect(AhoyDashboard::AiVisibility.frequency).to eq("weekly")
      expect(AhoyDashboard::AiVisibility::Answer.count).to eq(2)
    end

    it "deletes the prompt and every answer to it once confirmed" do
      doomed = create(:dash_ai_prompt, text: "drop", position: 0)
      answer = create(:dash_ai_answer, prompt: doomed)
      create(:dash_ai_source, answer: answer)

      save(prompts: "new one", confirm: "1")

      expect(response).to redirect_to("/telemetry/settings/ai_visibility/edit")
      expect(texts).to eq([ "new one" ])
      expect(AhoyDashboard::AiVisibility::Answer.count).to be_zero
      expect(AhoyDashboard::AiVisibility::Source.count).to be_zero
    end

    it "refuses a cap that is not a whole number of requests" do
      save(prompts: "a question", monthly_cap: "-3")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has to be a whole number of requests")
      expect(AhoyDashboard::AiVisibility::Prompt.count).to be_zero
    end

    it "refuses a frequency it does not know" do
      save(prompts: "a question", frequency: "hourly")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has to be daily, weekly or monthly")
    end

    it "refuses a prompt that is too long" do
      save(prompts: "x" * (AhoyDashboard::AiVisibility::Prompt::MAX_LENGTH + 1))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("one line is longer")
    end

    it "refuses more prompts than it will ask" do
      limit = AhoyDashboard::AiVisibility::SettingsForm::MAX_PROMPTS

      save(prompts: (1..(limit + 1)).map { |n| "question #{n}" }.join("\n"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("at most #{limit} prompts")
    end
  end
end
