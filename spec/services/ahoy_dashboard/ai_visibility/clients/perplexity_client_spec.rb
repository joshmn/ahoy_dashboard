require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::Clients::PerplexityClient do
  let(:endpoint) { "https://api.perplexity.ai/chat/completions" }
  let(:client) { described_class.new(api_key: "pplx-test", model: "sonar") }

  it "reads the citations in order, with titles from the search results" do
    body = {
      "model" => "sonar",
      "choices" => [ { "message" => { "role" => "assistant", "content" => "Try one [1][2]." } } ],
      "citations" => [ "https://rival.example/a", "https://federalprisondude.com/" ],
      "search_results" => [ { "title" => "FPD", "url" => "https://federalprisondude.com/" },
                            { "title" => "Rival A", "url" => "https://rival.example/a" } ]
    }
    stub = stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer pplx-test" },
            body: { model: "sonar", messages: [ { role: "user", content: "who?" } ] }.to_json)
      .to_return(status: 200, body: body.to_json)

    reply = client.ask("who?")

    expect(stub).to have_been_made
    expect(reply.text).to eq("Try one [1][2].")
    expect(reply.sources.map { |source| [ source.url, source.title ] })
      .to eq([ [ "https://rival.example/a", "Rival A" ], [ "https://federalprisondude.com/", "FPD" ] ])
  end

  it "reads citations with no titles when there are no search results" do
    body = { "choices" => [ { "message" => { "content" => "x" } } ], "citations" => [ "https://rival.example/" ] }
    stub_request(:post, endpoint).to_return(status: 200, body: body.to_json)

    reply = client.ask("who?")

    expect(reply.sources.map(&:url)).to eq([ "https://rival.example/" ])
    expect(reply.sources.first.title).to be_nil
  end

  it "falls back to the search results when there are no citations" do
    body = { "choices" => [ { "message" => { "content" => "x" } } ],
             "search_results" => [ { "title" => "Rival", "url" => "https://rival.example/" } ] }
    stub_request(:post, endpoint).to_return(status: 200, body: body.to_json)

    expect(client.ask("who?").sources.map(&:title)).to eq([ "Rival" ])
  end

  it "maps a 401 to an auth error" do
    stub_request(:post, endpoint).to_return(status: 401, body: { error: { message: "Invalid API key" } }.to_json)

    expect { client.ask("x") }.to raise_error(AhoyDashboard::AiVisibility::AuthError, "perplexity returned 401: Invalid API key")
  end
end
