require "rails_helper"

RSpec.describe "Dashboard AI visibility key removal", type: :request do
  def store_secret
    create(:dash_ai_assistant, :keyed)
  end

  let(:path) { "/telemetry/settings/ai_visibility_assistants/openai/secrets/api_key" }

  around { |example| ai_visibility_settings(enabled: true) { example.run } }

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    include_examples "a stored secret removal",
                     secret_path: "/telemetry/settings/ai_visibility_assistants/openai/secrets/api_key",
                     confirm_path: "/telemetry/settings/ai_visibility_assistants/openai/edit?remove=api_key",
                     edit_path: "/telemetry/settings/ai_visibility_assistants/openai/edit",
                     word: "key", nothing: "There was no ChatGPT key stored.", model: AhoyDashboard::AiVisibility::Assistant,
                     unknown: {
                       "a key the assistant does not take" => "/telemetry/settings/ai_visibility_assistants/openai/secrets/model",
                       "an assistant nobody registered" => "/telemetry/settings/ai_visibility_assistants/copilot/secrets/api_key"
                     }


    it "offers Remove beside a stored key and not otherwise" do
      create(:dash_ai_assistant, :keyed)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit"
      link = document.at_css("a[aria-label='Remove the stored ChatGPT key']")
      expect(link["href"]).to eq("/telemetry/settings/ai_visibility_assistants/openai/edit?remove=api_key#remove-secret")

      get "/telemetry/settings/ai_visibility_assistants/gemini/edit"
      expect(document.at_css("a[aria-label^='Remove the stored']")).to be_nil
    end

    it "asks first, saying the assistant stops being asked" do
      create(:dash_ai_assistant, :keyed)
      create(:dash_ai_prompt)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit", params: { remove: "api_key" }

      document = Nokogiri::HTML5(response.body)
      expect(document.at_css("#remove-secret").text)
        .to include("Remove the stored ChatGPT key? ChatGPT stops being asked until a key is saved again.")
      expect(document.at_css("#remove-secret form[action='#{path}'] input[name='_method'][value='delete']")).to be_present
    end

    it "says nothing asks it while there are no prompts" do
      create(:dash_ai_assistant, :keyed)

      get "/telemetry/settings/ai_visibility_assistants/openai/edit", params: { remove: "api_key" }

      expect(response.body).to include("Nothing asks ChatGPT until AI visibility is on and has prompts.")
    end

    it "deletes the key and keeps the row and its models" do
      create(:dash_ai_assistant, :keyed, models: %w[gpt-4.1])

      delete path

      expect(response).to redirect_to("/telemetry/settings/ai_visibility_assistants/openai/edit")
      expect(flash[:notice]).to eq("ChatGPT key removed.")
      assistant = AhoyDashboard::AiVisibility::Assistant.for("openai")
      expect(assistant.read_attribute(:credentials)).to be_nil
      expect(assistant.models).to eq(%w[gpt-4.1])
      expect(AhoyDashboard::AiVisibility.asked_names).not_to include("openai")
    end

    it "reads Nothing stored once the stored key is gone, whatever the environment holds" do
      create(:dash_ai_assistant, :keyed)
      stub_const("ENV", ENV.to_h.merge("OPENAI_API_KEY" => "from-env"))

      delete path
      get "/telemetry/settings/ai_visibility_assistants/openai/edit"

      expect(AhoyDashboard::AiVisibility.api_key("openai")).to be_nil
      expect(response.body).to include("Nothing stored.")
    end
  end
end
