require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Clients::AnthropicClient do
  let(:endpoint) { "https://api.anthropic.com/v1/messages" }
  let(:transport) { AhoyDashboard::LLM::Transport.new(sleeper: ->(_seconds) { }) }
  let(:client) { described_class.new(api_key: "sk-ant-test", model: "claude-opus-5", transport: transport) }

  def frame(type, payload = {})
    "event: #{type}\ndata: #{JSON.generate(payload.merge("type" => type))}\n\n"
  end

  def streamed(message)
    blocks = Array(message["content"]).each_with_index.map do |block, index|
      opened = case block["type"]
      when "text" then { "type" => "text", "text" => "" }
      when "thinking" then { "type" => "thinking", "thinking" => "" }
      when "server_tool_use" then block.merge("input" => {})
      else block
      end
      deltas = case block["type"]
      when "text"
                 [ { "type" => "text_delta", "text" => block["text"] } ] +
                   Array(block["citations"]).map { |cite| { "type" => "citations_delta", "citation" => cite } }
      when "thinking" then [ { "type" => "signature_delta", "signature" => block["signature"] } ]
      when "server_tool_use" then [ { "type" => "input_json_delta", "partial_json" => JSON.generate(block["input"]) } ]
      else []
      end

      frame("content_block_start", "index" => index, "content_block" => opened) +
        deltas.map { |delta| frame("content_block_delta", "index" => index, "delta" => delta) }.join +
        frame("content_block_stop", "index" => index)
    end

    frame("message_start", "message" => { "model" => message["model"], "content" => [], "usage" => {} }) +
      blocks.join +
      frame("message_delta", "delta" => { "stop_reason" => message["stop_reason"] }, "usage" => { "output_tokens" => 1 }) +
      frame("message_stop")
  end

  def cite(url, title)
    { "type" => "web_search_result_location", "url" => url, "title" => title, "cited_text" => "..." }
  end

  let(:search_turn) do
    [
      { "type" => "thinking", "thinking" => "", "signature" => "sig" },
      { "type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => { "query" => "consultants" } },
      { "type" => "web_search_tool_result", "tool_use_id" => "srvtoolu_1",
        "content" => [ { "type" => "web_search_result", "url" => "https://uncited.example/", "title" => "Uncited" } ] }
    ]
  end

  it "asks with the web search tool and reads cited links, not every search result" do
    body = { "model" => "claude-opus-5", "stop_reason" => "end_turn", "content" => search_turn + [
      { "type" => "text", "text" => "Federal Prison Consulting ", "citations" => [ cite("https://federalprisondude.com/", "FPD") ] },
      { "type" => "text", "text" => "is one option.", "citations" => [ cite("https://rival.example/", "Rival") ] }
    ] }
    stub = stub_request(:post, endpoint)
      .with(headers: { "x-api-key" => "sk-ant-test", "anthropic-version" => "2023-06-01" }) { |request|
        sent = JSON.parse(request.body)
        sent["model"] == "claude-opus-5" && sent["max_tokens"] == described_class::MAX_TOKENS && sent["stream"] == true &&
          sent["tools"] == [ { "type" => "web_search_20260209", "name" => "web_search", "max_uses" => 5 } ] &&
          sent["messages"] == [ { "role" => "user", "content" => "who helps?" } ] &&
          !sent.key?("thinking") && !sent.key?("fallbacks")
      }
      .to_return(status: 200, body: streamed(body))

    reply = client.ask("who helps?")

    expect(stub).to have_been_made
    expect(reply.text).to eq("Federal Prison Consulting is one option.")
    expect(reply.sources.map(&:url)).to eq([ "https://federalprisondude.com/", "https://rival.example/" ])
  end

  {
    "claude-sonnet-5" => "web_search_20260209",
    "claude-opus-4-6" => "web_search_20260209",
    "claude-haiku-4-5" => "web_search_20250305",
    "claude-opus-4-5" => "web_search_20250305",
    "claude-sonnet-4-5" => "web_search_20250305"
  }.each do |model, tool|
    it "sends #{model} the #{tool} search tool" do
      body = { "model" => model, "stop_reason" => "end_turn", "content" => [ { "type" => "text", "text" => "Hi." } ] }
      stub = stub_request(:post, endpoint)
        .with { |request| JSON.parse(request.body)["tools"].first["type"] == tool }
        .to_return(status: 200, body: streamed(body))

      described_class.new(api_key: "sk-ant-test", model: model).ask("who helps?")

      expect(stub).to have_been_made
    end
  end

  it "resumes a paused turn by sending the paused content back as the assistant turn" do
    paused = { "model" => "claude-opus-5", "stop_reason" => "pause_turn", "content" => search_turn }
    finished = { "model" => "claude-opus-5", "stop_reason" => "end_turn", "content" => [
      { "type" => "text", "text" => "Done.", "citations" => [ cite("https://rival.example/", "Rival") ] }
    ] }
    requests = []
    stub_request(:post, endpoint).to_return do |request|
      requests << JSON.parse(request.body)
      { status: 200, body: streamed(requests.size == 1 ? paused : finished) }
    end

    reply = client.ask("who helps?")

    expect(requests.size).to eq(2)
    expect(requests.last["messages"].map { |message| message["role"] }).to eq(%w[user assistant])
    expect(requests.last["messages"].last["content"]).to eq(search_turn)
    expect(reply.text).to eq("Done.")
    expect(reply.sources.map(&:url)).to eq([ "https://rival.example/" ])
  end

  it "stops resuming after three continuations" do
    paused = { "stop_reason" => "pause_turn", "content" => [ { "type" => "text", "text" => "a" } ] }
    stub = stub_request(:post, endpoint).to_return(status: 200, body: streamed(paused))

    expect(client.ask("x").text).to eq("aaaa")
    expect(stub).to have_been_made.times(4)
  end

  it "raises when the model declines" do
    stub_request(:post, endpoint).to_return(status: 200, body: streamed({ "stop_reason" => "refusal", "content" => [] }))

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, "claude declined to answer")
  end

  it "raises rather than recording an answer the output limit cut off" do
    cut = { "stop_reason" => "max_tokens", "content" => [ { "type" => "text", "text" => "Federal Prison" } ] }
    stub_request(:post, endpoint).to_return(status: 200, body: streamed(cut))

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, /cut off/)
  end

  it "retries an overloaded answer before giving up on it" do
    done = { "model" => "claude-opus-5", "stop_reason" => "end_turn", "content" => [ { "type" => "text", "text" => "Hi." } ] }
    stub = stub_request(:post, endpoint).to_return({ status: 529, body: "{}" }, { status: 200, body: streamed(done) })

    expect(client.ask("x").text).to eq("Hi.")
    expect(stub).to have_been_made.twice
  end

  it "maps a 403 to an auth error and a 429 to a quota error" do
    stub_request(:post, endpoint).to_return({ status: 403, body: { error: { message: "denied" } }.to_json },
                                            { status: 429, body: "{}" })

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::AuthError, "anthropic returned 403: denied")
    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::QuotaError)
  end
end
