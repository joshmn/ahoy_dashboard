require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::MatchService do
  def source(url, title = nil)
    AhoyDashboard::AiVisibility::ReplySource.new(url: url, title: title)
  end

  def call(text: "", sources: [], own: "federalprisondude.com", terms: [ "Federal Prison Dude" ])
    described_class.call(text: text, sources: sources, own: own, terms: terms)
  end

  it "counts a mention of a brand term ignoring case, spaces and hyphens" do
    expect(call(text: "Ask the federal-prison dude about it.").mentioned).to be(true)
    expect(call(text: "FEDERALPRISONDUDE is one.").mentioned).to be(true)
    expect(call(text: "Ask a lawyer.").mentioned).to be(false)
  end

  it "counts a mention of the domain itself" do
    expect(call(text: "See federalprisondude.com", terms: []).mentioned).to be(true)
  end

  it "marks our domain and its subdomains as ours and finds the first position" do
    result = call(sources: [ source("https://rival.example/"), source("https://www.federalprisondude.com/faq"),
                             source("https://portal.federalprisondude.com/") ])

    expect(result.sources.map(&:ours)).to eq([ false, true, true ])
    expect(result.sources.map(&:domain)).to eq(%w[rival.example federalprisondude.com portal.federalprisondude.com])
    expect(result.cited).to be(true)
    expect(result.position).to eq(2)
  end

  it "does not count a lookalike domain" do
    result = call(sources: [ source("https://notfederalprisondude.com/") ])

    expect(result.cited).to be(false)
    expect(result.position).to be_nil
  end

  it "can cite without mentioning, and mention without citing" do
    cited = call(text: "Here is a list.", sources: [ source("https://federalprisondude.com/") ])
    mentioned = call(text: "Federal Prison Dude is good.", sources: [ source("https://rival.example/") ])

    expect([ cited.mentioned, cited.cited ]).to eq([ false, true ])
    expect([ mentioned.mentioned, mentioned.cited ]).to eq([ true, false ])
  end

  it "reads the domain from the title behind a google grounding redirect" do
    result = call(sources: [ source("https://vertexaisearch.cloud.google.com/grounding-api-redirect/x", "federalprisondude.com"),
                             source("https://vertexaisearch.cloud.google.com/grounding-api-redirect/y", "Some Page Title") ])

    expect(result.sources.map(&:domain)).to eq(%w[federalprisondude.com vertexaisearch.cloud.google.com])
    expect(result.position).to eq(1)
  end

  it "defaults to the configured host and brand terms" do
    result = described_class.call(text: "example", sources: [ source("https://example.com/") ])

    expect([ result.mentioned, result.cited ]).to eq([ true, true ])
  end
end
