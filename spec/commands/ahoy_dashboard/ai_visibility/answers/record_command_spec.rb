require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Answers::RecordCommand do
  let(:endpoint) { "https://api.openai.com/v1/responses" }
  let(:run) { create(:dash_ai_run) }
  let(:prompt) { create(:dash_ai_prompt, text: "who helps with federal prison?") }
  def reply(text, *urls)
    annotations = urls.map { |url| { "type" => "url_citation", "url" => url, "title" => url } }
    response = { "model" => "gpt-4.1-2025-04-14", "status" => "completed",
                 "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => text, "annotations" => annotations } ] } ] }

    [ { "type" => "response.output_item.done", "output_index" => 0, "item" => response["output"].first },
      { "type" => "response.completed", "response" => response } ]
      .map { |event| "event: #{event["type"]}\ndata: #{JSON.generate(event)}\n\n" }.join
  end

  it "stores the answer, what it found and every source in order" do
    assistant = create(:dash_ai_assistant, :keyed, last_error: "old", last_error_at: 1.day.ago)
    stub_request(:post, endpoint).to_return(status: 200, body: reply("Example is good.", "https://rival.example/", "https://www.example.com/x"))

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    answer = events[:ok]
    expect(answer).to be_success
    expect(answer.text).to eq("Example is good.")
    expect(answer.model).to eq("gpt-5")
    expect(answer.served_model).to eq("gpt-4.1-2025-04-14")
    expect([ answer.mentioned, answer.cited, answer.position ]).to eq([ true, true, 2 ])
    expect(answer.sources.map { |source| [ source.slot, source.domain, source.ours ] })
      .to eq([ [ 1, "rival.example", false ], [ 2, "example.com", true ] ])
    expect(assistant.reload.last_error).to be_nil
    expect(assistant.last_used_at).to be_present
  end

  it "stores a failed answer and the error when the request fails" do
    assistant = create(:dash_ai_assistant, :keyed)
    stub_request(:post, endpoint).to_return(status: 401, body: { error: { message: "bad key" } }.to_json)

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    answer = events[:failed]
    expect(answer).to be_failed
    expect(answer.error).to eq("openai returned 401: bad key")
    expect(answer.text).to be_nil
    expect(answer.model).to eq("gpt-5")
    expect(assistant.reload.last_error).to eq("gpt-5: openai returned 401: bad key")
    expect(AhoyDashboard::AiVisibility.used_this_month).to eq(1)
  end

  it "records a failure without sending anything when the key is gone" do
    create(:dash_ai_assistant)

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    expect(events[:failed].error).to eq("no key")
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  it "sends nothing when no key is stored, whatever the environment holds" do
    stub_const("ENV", ENV.to_h.merge("OPENAI_API_KEY" => "from-env"))

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    expect(events[:failed].error).to eq("no key")
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  it "sends the model it was handed" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-5 gpt-4.1])
    stub = stub_request(:post, endpoint).with(body: hash_including("model" => "gpt-4.1"))
      .to_return(status: 200, body: reply("Nothing about us."))

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-4.1")

    expect(stub).to have_been_made
    expect(events[:ok].model).to eq("gpt-4.1")
  end

  it "asks a second model the same prompt in the same run" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-5 gpt-4.1])
    create(:dash_ai_answer, run: run, prompt: prompt, assistant: "openai", model: "gpt-4.1")
    stub_request(:post, endpoint).to_return(status: 200, body: reply("Nothing about us."))

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    expect(events).to have_key(:ok)
    expect(AhoyDashboard::AiVisibility::Answer.pluck(:model)).to contain_exactly("gpt-4.1", "gpt-5")
  end

  it "asks nothing a second time for the same run, prompt, assistant and model" do
    create(:dash_ai_assistant, :keyed)
    create(:dash_ai_answer, run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    events = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    expect(events).to have_key(:duplicate)
    expect(a_request(:post, endpoint)).not_to have_been_made
    expect(AhoyDashboard::AiVisibility::Answer.count).to eq(1)
  end

  it "claims a request before HTTP so duplicate delivery cannot spend twice" do
    create(:dash_ai_assistant, :keyed)
    duplicate = nil
    stub_request(:post, endpoint).to_return do
      duplicate = described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")
      { status: 200, body: reply("Nothing about us.") }
    end

    described_class.call(run: run, prompt: prompt, assistant: "openai", model: "gpt-5")

    expect(duplicate).to have_key(:duplicate)
  end
end
