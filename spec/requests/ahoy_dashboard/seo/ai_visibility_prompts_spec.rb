require "rails_helper"

RSpec.describe "Dashboard AI visibility prompt", type: :request do
  let(:prompt) { create(:dash_ai_prompt, text: "best federal prison consultant") }

  before { sign_in create(:user, :admin) }

  it "is a 404 for a prompt that does not exist" do
    get "/telemetry/seo/ai_visibility/prompts/0"

    expect(response).to have_http_status(:not_found)
  end

  it "shows every answer grouped by assistant and model, newest first, with sources and badges" do
    older = create(:dash_ai_answer, prompt: prompt, text: "Older answer.", asked_at: 3.days.ago)
    newer = create(:dash_ai_answer, prompt: prompt, text: "Newer answer.", mentioned: true, cited: true, position: 1,
                                    asked_at: 1.day.ago)
    create(:dash_ai_answer, :failed, prompt: prompt, assistant: "anthropic", model: "claude-opus-5")
    create(:dash_ai_source, answer: newer, domain: "federalprisondude.com", ours: true, url: "https://federalprisondude.com/x")

    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}"

    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to include("best federal prison consultant")
    headings = document.css(".card-title").map { |node| node.text.squish }
    expect(headings).to include("ChatGPT (gpt-4.1)", "Claude (claude-opus-5)")
    texts = document.css("details").map { |node| node.text.squish }
    expect(texts.index { |text| text.include?("Newer answer.") }).to be < texts.index { |text| text.include?("Older answer.") }
    expect(document.text.squish).to include("Cited, position 1", "Failed", "openai returned 500")
    expect(document.at_css("a[href='https://federalprisondude.com/x']")).to be_present
    expect(older).to be_persisted
  end

  it "gives each model of one assistant its own group, and says when the provider served another version" do
    create(:dash_ai_answer, prompt: prompt, model: "gpt-5", served_model: "gpt-5-2025-08-07", text: "From five.")
    create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1", served_model: "gpt-4.1", text: "From four.")

    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}"

    headings = document.css(".card-title").map { |node| node.text.squish }
    expect(headings).to include("ChatGPT (gpt-4.1)", "ChatGPT (gpt-5)")
    expect(document.text.squish).to include("served as gpt-5-2025-08-07")
    expect(document.text.squish).not_to include("served as gpt-4.1")
  end

  it "narrows to one model and keeps it on the way back" do
    create(:dash_ai_answer, prompt: prompt, model: "gpt-5", text: "From five.")
    create(:dash_ai_answer, prompt: prompt, model: "gpt-4.1", text: "From four.")

    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}", params: { assistant: "openai", model: "gpt-5" }

    expect(document.text).to include("From five.")
    expect(document.text).not_to include("From four.")
    back = document.css("a").find { |link| link.text.squish == "All prompts" }
    expect(back["href"]).to include("assistant=openai", "model=gpt-5")
  end

  it "escapes whatever the provider wrote" do
    create(:dash_ai_answer, prompt: prompt, text: "Try <script>alert(1)</script> now.")

    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}"

    expect(response.body).not_to include("<script>alert(1)</script>")
    expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
  end

  it "marks where you are mentioned" do
    AhoyDashboard::Setting.write(AhoyDashboard::Seo::BrandTerms::KEY, [ "Federal Prison Dude" ])
    create(:dash_ai_answer, prompt: prompt, text: "Ask federal-prison dude about it.", mentioned: true)

    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}"

    expect(document.at_css("mark").text).to eq("federal-prison dude")
  end

  it "says so when the prompt has not been asked" do
    get "/telemetry/seo/ai_visibility/prompts/#{prompt.id}"

    expect(document.text.squish).to include("Not asked yet")
  end
end
