require "rails_helper"

RSpec.describe "Dashboard prompt suggestions in Ask", type: :request do
  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  let(:chat) { create(:dash_chat) }
  let(:frame) { AhoyDashboard::ChatsController::THREAD_FRAME }

  def suggest!(*texts)
    views = AhoyDashboard::Assistant::Views.new
    AhoyDashboard::Assistant::Tools::ProposePrompts.new(views: views)
      .execute(prompts: texts.map { |text| { "text" => text, "because" => "landed on /compare" } })
    create(:dash_chat_message, :assistant, chat: chat, content: "Here are three.",
                                           tool_calls: [ { "name" => "propose_prompts" } ], views: views.to_json_ready)
  end

  def add(*texts, headers: {})
    post "/telemetry/chats/#{chat.id}/prompts", params: { prompts: { texts: texts } }, headers: headers
  end

  def tracked
    AhoyDashboard::AiVisibility::Prompt.ordered.pluck(:text)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "shows each suggestion with its reason, an add button that stays in the thread, and the cost" do
      create(:dash_ai_assistant, :keyed, name: "openai")
      suggest!("what is a good analytics tool", "which analytics tool is cheapest")

      get "/telemetry/chats/#{chat.id}"
      document = Nokogiri::HTML5(response.body)

      items = document.css(".chat-proposals__item")
      expect(items.map { |item| item.at_css(".chat-proposals__text").text })
        .to eq([ "what is a good analytics tool", "which analytics tool is cheapest" ])
      expect(items.first.text).to include("landed on /compare")
      forms = document.css("form[action='/telemetry/chats/#{chat.id}/prompts']")
      expect(forms.size).to eq(3)
      expect(forms.map { |form| form["data-tm-frame"] }.uniq).to eq([ frame ])
      expect(forms.last.css("input[name='prompts[texts][]']").map { |input| input["value"] })
        .to eq([ "what is a good analytics tool", "which analytics tool is cheapest" ])
      expect(document.at_css(".chat-proposals__cost").text).to include("Each one adds 1 request a run, about 4 requests a month on Weekly")
    end

    it "marks one already tracked instead of offering it again" do
      suggest!("what is a good analytics tool", "which analytics tool is cheapest")
      create(:dash_ai_prompt, text: "What is a good analytics tool")

      get "/telemetry/chats/#{chat.id}"
      document = Nokogiri::HTML5(response.body)

      expect(document.css(".chat-proposals__item").first.text).to include("Tracked")
      expect(document.css("form[action='/telemetry/chats/#{chat.id}/prompts']").size).to eq(1)
    end

    it "adds the prompts after the ones already tracked and keeps their answers" do
      kept = create(:dash_ai_prompt, text: "already here", position: 4)
      create(:dash_ai_answer, prompt: kept)

      add("a new one", "Already here", "another new one")

      expect(response).to redirect_to("/telemetry/chats/#{chat.id}")
      expect(flash[:notice]).to eq("2 prompts added to AI visibility.")
      expect(tracked).to eq([ "already here", "a new one", "another new one" ])
      expect(kept.answers.count).to eq(1)
    end

    it "reloads only the thread when it is asked from inside it" do
      suggest!("what is a good analytics tool")

      add("what is a good analytics tool", headers: { "Tm-Frame" => frame })

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/telemetry/chats/#{chat.id}?view=thread")

      follow_redirect!(headers: { "Tm-Frame" => frame })
      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("tm-frame##{frame}")).to be_present
      expect(document.at_css(".chat-proposals__item").text).to include("Tracked")
    end

    it "says why when the set would be too big, inside the thread" do
      suggest!("one more")
      create_list(:dash_ai_prompt, AhoyDashboard::AiVisibility::SettingsForm::MAX_PROMPTS)

      add("one more", headers: { "Tm-Frame" => frame })

      expect(response).to have_http_status(422)
      expect(Nokogiri::HTML5(response.body).at_css(".chat-proposals__error").text)
        .to include("the set holds at most 100")
      expect(AhoyDashboard::AiVisibility::Prompt.count).to eq(100)
    end

    it "turns away a prompt that is too long" do
      add("x" * 501)

      expect(response).to redirect_to("/telemetry/chats/#{chat.id}")
      expect(flash[:alert]).to include("500 characters")
      expect(tracked).to be_empty
    end
  end

  describe "as somebody who can read but not change settings" do
    around do |example|
      permissions = AhoyDashboard.config.authorize_action
      AhoyDashboard.config.authorize_action = ->(_controller, permission) { permission != :manage }
      example.run
    ensure
      AhoyDashboard.config.authorize_action = permissions
    end

    before { sign_in create(:user, :admin) }

    it "shows the suggestions without the buttons, and will not add one" do
      suggest!("what is a good analytics tool")

      get "/telemetry/chats/#{chat.id}"
      document = Nokogiri::HTML5(response.body)

      expect(document.at_css(".chat-proposals__item")).to be_present
      expect(document.at_css("form[action='/telemetry/chats/#{chat.id}/prompts']")).to be_nil
      expect(document.at_css(".chat-proposals__ft").text).to include("Someone who can change settings")

      add("what is a good analytics tool")

      expect(tracked).to be_empty
    end
  end
end
