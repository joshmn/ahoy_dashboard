require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Clients::GeminiClient do
  let(:endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" }
  let(:client) { described_class.new(api_key: "g-test", model: "gemini-2.5-flash", transport: quiet_transport) }

  let(:payload) do
    {
      "modelVersion" => "gemini-2.5-flash",
      "candidates" => [ {
        "content" => { "role" => "model", "parts" => [ { "text" => "Federal Prison Dude " }, { "text" => "helps." } ] },
        "groundingMetadata" => {
          "webSearchQueries" => [ "federal prison consultant" ],
          "groundingChunks" => [
            { "web" => { "uri" => "https://vertexaisearch.cloud.google.com/grounding-api-redirect/AbC", "title" => "federalprisondude.com" } },
            { "web" => { "uri" => "https://vertexaisearch.cloud.google.com/grounding-api-redirect/DeF", "title" => "rival.example" } }
          ]
        }
      } ]
    }
  end

  it "asks with google search grounding and keeps the redirect links as given" do
    stub = stub_request(:post, endpoint)
      .with(headers: { "x-goog-api-key" => "g-test" },
            body: { contents: [ { role: "user", parts: [ { text: "who?" } ] } ], tools: [ { google_search: {} } ] }.to_json)
      .to_return(status: 200, body: payload.to_json)

    reply = client.ask("who?")

    expect(stub).to have_been_made
    expect(reply.text).to eq("Federal Prison Dude helps.")
    expect(reply.sources.map(&:url)).to all(start_with("https://vertexaisearch.cloud.google.com/"))
    expect(reply.sources.map(&:title)).to eq(%w[federalprisondude.com rival.example])
  end

  it "answers with no sources when nothing was grounded" do
    stub_request(:post, endpoint).to_return(status: 200, body: { "candidates" => [ { "content" => { "parts" => [ { "text" => "Hi" } ] } } ] }.to_json)

    reply = client.ask("who?")

    expect(reply.sources).to be_empty
    expect(reply.model).to eq("gemini-2.5-flash")
  end

  it "maps a 429 to a quota error once the retries are spent" do
    stub = stub_request(:post, endpoint).to_return(status: 429, body: { error: { message: "Resource exhausted" } }.to_json)

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::QuotaError, "gemini returned 429: Resource exhausted")
    expect(stub).to have_been_made.times(3)
  end

  it "retries a server error the same way the other assistants do" do
    stub = stub_request(:post, endpoint).to_return({ status: 503, body: "{}" }, { status: 200, body: payload.to_json })

    expect(client.ask("x").text).to eq("Federal Prison Dude helps.")
    expect(stub).to have_been_made.twice
  end

  it "asks again when the connection never opened" do
    stub = stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED).then.to_return(status: 200, body: payload.to_json)

    expect(client.ask("x").text).to eq("Federal Prison Dude helps.")
    expect(stub).to have_been_made.twice
  end

  it "does not ask again after a read timeout, because that answer may already be billed" do
    stub = stub_request(:post, endpoint).to_raise(Net::ReadTimeout)

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::Error, /gemini request failed: .*Net::ReadTimeout/)
    expect(stub).to have_been_made.once
  end
end
