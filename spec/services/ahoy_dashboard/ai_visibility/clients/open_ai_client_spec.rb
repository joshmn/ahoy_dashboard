require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Clients::OpenAiClient do
  let(:endpoint) { "https://api.openai.com/v1/responses" }
  let(:client) { described_class.new(api_key: "sk-test", model: "gpt-4.1", transport: quiet_transport) }

  def streamed(response, finished: "response.completed")
    items = Array(response["output"]).each_with_index.map do |item, index|
      openai_frame("type" => "response.output_item.done", "output_index" => index, "item" => item)
    end

    openai_frame("type" => "response.created", "response" => response.merge("output" => [])) + items.join +
      openai_frame("type" => finished, "response" => response)
  end

  let(:payload) do
    {
      "model" => "gpt-4.1-2025-04-14",
      "output" => [
        { "type" => "web_search_call", "id" => "ws_1", "status" => "completed" },
        { "type" => "message", "role" => "assistant", "content" => [
          { "type" => "output_text", "text" => "Try Federal Prison Consulting.",
            "annotations" => [
              { "type" => "url_citation", "url" => "https://federalprisondude.com/", "title" => "Federal Prison Dude",
                "start_index" => 4, "end_index" => 30 },
              { "type" => "url_citation", "url" => "https://rival.example/", "title" => "Rival" },
              { "type" => "url_citation", "url" => "https://federalprisondude.com/", "title" => "Federal Prison Dude" }
            ] }
        ] }
      ]
    }
  end

  it "asks with web search on and reads the text and its cited links in order" do
    stub = stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer sk-test" },
            body: { model: "gpt-4.1", input: "best consultant?", tools: [ { type: "web_search" } ], store: false,
                    stream: true }.to_json)
      .to_return(status: 200, body: streamed(payload))

    reply = client.ask("best consultant?")

    expect(stub).to have_been_made
    expect(reply.text).to eq("Try Federal Prison Consulting.")
    expect(reply.sources.map(&:url)).to eq([ "https://federalprisondude.com/", "https://rival.example/" ])
    expect(reply.sources.first.title).to eq("Federal Prison Dude")
    expect(reply.model).to eq("gpt-4.1-2025-04-14")
  end

  it "raises an auth error on a 401 with the provider's message" do
    stub_request(:post, endpoint).to_return(status: 401, body: { error: { message: "Incorrect API key provided" } }.to_json)

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::AuthError, "openai returned 401: Incorrect API key provided")
  end

  it "raises a quota error on a 429" do
    stub_request(:post, endpoint).to_return(status: 429, body: "{}")

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::QuotaError, "openai returned 429")
  end

  it "raises a plain error on anything else" do
    stub_request(:post, endpoint).to_return(status: 500, body: "oops")

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, "openai returned 500: oops")
  end

  it "retries a 500 before giving up on it" do
    stub = stub_request(:post, endpoint).to_return({ status: 500, body: "oops" }, { status: 200, body: streamed(payload) })

    expect(client.ask("x").text).to eq("Try Federal Prison Consulting.")
    expect(stub).to have_been_made.twice
  end

  it "raises rather than recording an answer the output limit cut off" do
    cut = payload.merge("status" => "incomplete", "incomplete_details" => { "reason" => "max_output_tokens" })
    stub_request(:post, endpoint).to_return(status: 200, body: streamed(cut, finished: "response.incomplete"))

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, /cut off/)
  end

  it "raises when the model refuses" do
    refused = payload.merge("output" => [ { "type" => "message", "role" => "assistant",
                                            "content" => [ { "type" => "refusal", "refusal" => "no" } ] } ])
    stub_request(:post, endpoint).to_return(status: 200, body: streamed(refused))

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, "chatgpt declined to answer")
  end

  it "refuses to send anything without a key" do
    expect { described_class.new(api_key: nil, model: "gpt-4.1").ask("x") }
      .to raise_error(AhoyDashboard::AiVisibility::AuthError, "openai has no key")
  end

  it "retries a dropped connection twice, then gives up with an error" do
    stub = stub_request(:post, endpoint).to_raise(Errno::ECONNRESET)

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, /openai request failed/)
    expect(stub).to have_been_made.times(3)
  end
end
