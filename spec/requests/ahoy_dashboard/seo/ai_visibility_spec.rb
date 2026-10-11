require "rails_helper"

RSpec.describe "Dashboard AI visibility", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  def tile(label)
    document.css(".tile").find { |node| node.at_css(".tile-label")&.text&.squish == label }&.at_css(".tile-value")&.text&.squish
  end

  let(:prompt) { create(:dash_ai_prompt, text: "who helps with federal prison prep") }

  def enable!
    allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true)
    create(:dash_ai_assistant, :keyed, name: "openai")
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/seo/ai_visibility"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      get "/telemetry/seo/ai_visibility"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "says it is off" do
      allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(false)

      get "/telemetry/seo/ai_visibility"

      expect(response).to have_http_status(:ok)
      expect(document.text.squish).to include("Turn on AI visibility to get started")
      expect(document.at_css("button[disabled]").text).to include("Run now")
    end

    it "points at settings when no assistant has a key" do
      allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true)

      get "/telemetry/seo/ai_visibility"

      expect(document.text.squish).to include("Turn on an assistant to get started")
      expect(document.at_css("a[href='/telemetry/settings/ai_visibility/edit']")).to be_present
    end

    it "points at settings when the only keyed assistant is off" do
      allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true)
      create(:dash_ai_assistant, :keyed, enabled: false)
      prompt

      get "/telemetry/seo/ai_visibility"

      expect(document.text.squish).to include("Turn on an assistant to get started", "No assistant is on with a key.")
      expect(document.at_css("a[href='/telemetry/settings/ai_visibility/edit']")).to be_present
    end

    it "points at settings when there are no prompts" do
      enable!

      get "/telemetry/seo/ai_visibility"

      expect(document.text.squish).to include("Write your prompts to get started")
    end

    it "says there are no answers yet once it is set up" do
      enable!
      prompt

      get "/telemetry/seo/ai_visibility"

      expect(document.text.squish).to include("No answers in this range")
      expect(document.at_css("form[action='/telemetry/seo/ai_visibility/runs'] button[data-tm-confirm]")["data-tm-confirm"])
        .to include("1 paid request", "monthly cap")
    end

    it "disables Run now when the run would not fit the cap" do
      enable!
      prompt
      AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
      create(:dash_ai_answer, prompt: prompt)

      get "/telemetry/seo/ai_visibility"

      notice = document.css("[role=status]").find { |node| node.text.include?("Run now is off.") }

      expect(notice.text.squish).to include("A run needs 1 requests and 0 are left this month.")
      expect(notice.at_css("a")["href"]).to eq("/telemetry/settings/ai_visibility/edit")
      expect(document.at_css("form[action='/telemetry/seo/ai_visibility/runs']")).to be_nil
    end

    it "shows the tiles worked out from the answers" do
      enable!
      create(:dash_ai_answer, prompt: prompt, mentioned: true, cited: true, position: 1)
      create(:dash_ai_answer, prompt: prompt, assistant: "anthropic", mentioned: true)
      create(:dash_ai_answer, prompt: prompt, assistant: "gemini")
      create(:dash_ai_answer, prompt: prompt, assistant: "perplexity")

      get "/telemetry/seo/ai_visibility"

      expect(tile("Mention rate")).to eq("50%")
      expect(tile("Citation rate")).to eq("25%")
      expect(tile("Prompts")).to eq("1")
      expect(tile("Answers")).to eq("4")
      expect(tile("Used this month")).to eq("4")
      expect(document.text.squish).to include("of 200 requests", "of 4 answers")
    end

    it "narrows to one assistant and carries it into the date range links" do
      enable!
      create(:dash_ai_answer, prompt: prompt, mentioned: true)
      create(:dash_ai_answer, prompt: prompt, assistant: "anthropic")

      get "/telemetry/seo/ai_visibility", params: { assistant: "anthropic" }

      expect(tile("Mention rate")).to eq("0%")
      expect(tile("Answers")).to eq("1")
      expect(document.at_css("h1").text).to include("Claude")
      period_links = document.css("#tm-seo-period a, [id^='tm-seo-period'] a").map { |link| link["href"] }
      expect(period_links).to all(include("assistant=anthropic"))
    end

    it "breaks the table, the chart and the menu out by model" do
      enable!
      AhoyDashboard::AiVisibility::Assistant.for("openai").update!(models: %w[gpt-5 gpt-4.1])
      3.times do |days|
        create(:dash_ai_answer, prompt: prompt, model: "gpt-5", mentioned: true, asked_at: days.days.ago)
        create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1", asked_at: days.days.ago)
      end

      get "/telemetry/seo/ai_visibility"

      rows = document.css("[aria-label='By assistant and model'] table tbody tr").map { |row| row.text.squish }
      expect(rows).to contain_exactly(a_string_including("ChatGPT", "gpt-4.1", "0%"), a_string_including("ChatGPT", "gpt-5", "100%"))
      expect(document.at_css("svg|svg[aria-label^='Mention rate by assistant and model']", "svg" => "http://www.w3.org/2000/svg").css("svg|path", "svg" => "http://www.w3.org/2000/svg").size).to eq(2)
      expect(document.text.squish).to include("ChatGPT (gpt-4.1), 0%", "ChatGPT (gpt-5), 100%")
      menu = document.css("[id^='tm-seo-assistant'] a").map { |link| [ link.text.squish, link["href"] ] }
      expect(menu).to include([ "ChatGPT, gpt-5", a_string_including("assistant=openai", "model=gpt-5") ])
    end

    it "narrows to one model of one assistant" do
      enable!
      create(:dash_ai_answer, prompt: prompt, model: "gpt-5", mentioned: true)
      create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1")

      get "/telemetry/seo/ai_visibility", params: { assistant: "openai", model: "gpt-5" }

      expect(tile("Mention rate")).to eq("100%")
      expect(tile("Answers")).to eq("1")
      expect(document.at_css("h1").text).to include("ChatGPT (gpt-5)")
    end

    it "ignores a model without an assistant" do
      enable!
      create(:dash_ai_answer, prompt: prompt, model: "gpt-5")
      create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1")

      get "/telemetry/seo/ai_visibility", params: { model: "gpt-5" }

      expect(tile("Answers")).to eq("2")
    end

    it "ignores an assistant it does not know" do
      enable!
      create(:dash_ai_answer, prompt: prompt)

      get "/telemetry/seo/ai_visibility", params: { assistant: "bard" }

      expect(tile("Answers")).to eq("1")
    end

    it "lists the prompts you do not show up in and who gets cited instead" do
      enable!
      answer = create(:dash_ai_answer, prompt: prompt)
      create(:dash_ai_source, answer: answer, domain: "rival.example")

      get "/telemetry/seo/ai_visibility"

      expect(document.text).to include("who helps with federal prison prep", "rival.example")
    end

    it "says when a run was skipped for the cap" do
      enable!
      create(:dash_ai_answer, prompt: prompt)
      create(:dash_ai_run, status: "skipped", skip_reason: "A run needs 8 requests and 2 are left this month.")

      get "/telemetry/seo/ai_visibility"

      expect(document.text.squish).to include("A run was skipped.", "A run needs 8 requests and 2 are left this month.")
    end

    describe "CSV" do
      before do
        enable!
        answer = create(:dash_ai_answer, prompt: prompt, mentioned: true, cited: true, position: 2)
        create(:dash_ai_source, answer: answer, domain: "rival.example")
        create(:dash_ai_answer, prompt: prompt, assistant: "anthropic")
      end

      def csv
        CSV.parse(response.body)
      end

      it "exports the assistants table" do
        get "/telemetry/seo/ai_visibility.csv", params: { table: "assistants" }

        today = Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.iso8601
        expect(response.headers["Content-Disposition"]).to include("ahoy-dashboard-seo-ai-visibility-assistants-#{today}.csv")
        expect(csv.first).to eq([ "Assistant", "Model", "Answers", "Mentioned", "Cited", "Mention rate", "Citation rate", "Average position" ])
        expect(csv).to include([ "ChatGPT", "gpt-4.1", "1", "1", "1", "100.0", "100.0", "2.0" ])
      end

      it "exports the prompts you do not show up in" do
        get "/telemetry/seo/ai_visibility.csv", params: { table: "missing_prompts", assistant: "anthropic" }

        expect(csv.first).to eq([ "Prompt", "Models asked", "Last asked" ])
        expect(csv[1].first(2)).to eq([ "who helps with federal prison prep", "1" ])
      end

      it "exports who gets cited instead" do
        get "/telemetry/seo/ai_visibility.csv", params: { table: "cited_instead" }

        expect(csv).to eq([ [ "Domain", "Answers citing it", "Share of answers" ], [ "rival.example", "1", "50.0" ] ])
      end

      it "is a 404 for a table it does not have" do
        get "/telemetry/seo/ai_visibility.csv", params: { table: "answers" }

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
