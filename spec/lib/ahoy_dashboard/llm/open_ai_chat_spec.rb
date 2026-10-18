require "rails_helper"

RSpec.describe AhoyDashboard::LLM::OpenAI::Chat do
  let(:endpoint) { "https://api.openai.com/v1/responses" }
  let(:client) { AhoyDashboard::LLM::OpenAI::Client.new(api_base: "https://api.openai.com/v1", api_key: "k", transport: quiet_transport) }

  let(:adder) do
    Class.new(AhoyDashboard::LLM::Tool) do
      def self.name
        "AhoyDashboard::Spec::Adder"
      end

      desc "adds one"
      params do
        integer :a
        string :unit, required: false, enum: %w[ones tens]
      end

      def execute(a: 0, unit: "ones")
        { sum: a + 1, unit: unit }
      end
    end.new
  end

  let(:reasoning) { { "type" => "reasoning", "id" => "rs_1", "summary" => [], "encrypted_content" => "opaque" } }

  def chat(model: "gpt-6-sol", **options)
    described_class.new(client: client, model: model, **options)
  end

  def message(text)
    { "type" => "message", "role" => "assistant", "content" => [ { "type" => "output_text", "text" => text, "annotations" => [] } ] }
  end

  def call_item(call_id, arguments)
    { "type" => "function_call", "id" => "fc_#{call_id}", "call_id" => call_id, "name" => "adder", "arguments" => arguments }
  end

  def streamed(output, status: "completed", incomplete: nil, usage: { "input_tokens" => 100, "output_tokens" => 5,
                                                                          "input_tokens_details" => { "cached_tokens" => 80, "cache_write_tokens" => 0 } })
    deltas = output.each_with_index.flat_map do |item, index|
      texts = item["type"] == "message" ? item["content"].map { |part| part["text"].to_s } : []
      texts.map { |text| openai_frame("type" => "response.output_text.delta", "output_index" => index, "delta" => text) } +
        [ openai_frame("type" => "response.output_item.done", "output_index" => index, "item" => item) ]
    end
    response = { "id" => "resp_1", "status" => status, "output" => output, "usage" => usage,
                 "incomplete_details" => incomplete }
    finished = status == "incomplete" ? "response.incomplete" : "response.completed"

    openai_frame("type" => "response.created", "response" => response.merge("output" => [])) + deltas.join +
      openai_frame("type" => finished, "response" => response)
  end

  describe "the request" do
    it "uses the Responses API, keeps nothing on OpenAI's side, and keys the prompt cache" do
      stub_llm_replies(endpoint, streamed([ message("ok") ]))

      chat.with_instructions("be brief", context: "today is monday").ask("q")

      expect(WebMock).to have_requested(:post, endpoint).with(headers: { "Authorization" => "Bearer k" })
      expect(llm_requests.first).to include(
        "model" => "gpt-6-sol", "stream" => true, "store" => false,
        "instructions" => "be brief\n\ntoday is monday",
        "input" => [ { "role" => "user", "content" => "q" } ],
        "max_output_tokens" => AhoyDashboard::LLM::OpenAI::Models::MAX_TOKENS,
        "prompt_cache_key" => described_class::CACHE_KEY
      )
    end

    it "asks a reasoning model for its encrypted reasoning and sends it no temperature" do
      stub_llm_replies(endpoint, streamed([ message("ok") ]))

      chat.with_temperature(0.2).ask("q")

      expect(llm_requests.first["include"]).to eq([ "reasoning.encrypted_content" ])
      expect(llm_requests.first).not_to have_key("temperature")
    end

    it "sends the temperature to a model that is not a reasoning model" do
      stub_llm_replies(endpoint, streamed([ message("ok") ]))

      chat(model: "gpt-4.1").with_temperature(0.2).ask("q")

      expect(llm_requests.first["temperature"]).to eq(0.2)
      expect(llm_requests.first).not_to have_key("include")
    end

    it "sends strict tools with every field required and the optional ones nullable" do
      stub_llm_replies(endpoint, streamed([ message("ok") ]))

      chat.with_tools(adder).ask("q")

      expect(llm_requests.first["tools"]).to eq([ {
        "type" => "function", "name" => "adder", "description" => "adds one", "strict" => true,
        "parameters" => { "type" => "object", "additionalProperties" => false, "required" => %w[a unit],
                          "properties" => { "a" => { "type" => "integer" },
                                            "unit" => { "type" => %w[string null], "enum" => [ "ones", "tens", nil ] } } }
      } ])
      expect(llm_requests.first["tool_choice"]).to eq("auto")
    end
  end

  describe "an answer" do
    it "streams the text and reads cached input off the usage" do
      stub_llm_replies(endpoint, streamed([ message("Traffic is up.") ]))

      seen = []
      answer = chat.ask("q") { |chunk| seen << chunk.content }

      expect(seen).to eq([ "Traffic is up." ])
      expect(answer.content).to eq("Traffic is up.")
      expect(answer.input_tokens).to eq(100)
      expect(answer.cache_read_tokens).to eq(80)
    end

    it "marks an answer the output limit cut off" do
      stub_llm_replies(endpoint, streamed([ message("Traffic is") ], status: "incomplete", incomplete: { "reason" => "max_output_tokens" }))

      expect(chat.ask("q")).to be_truncated
    end

    it "raises on a refusal" do
      refusal = { "type" => "message", "role" => "assistant", "content" => [ { "type" => "refusal", "refusal" => "no" } ] }
      stub_llm_replies(endpoint, streamed([ refusal ]))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::RefusedError)
    end

    it "raises when the stream reports an error" do
      stub_llm_replies(endpoint, openai_frame("type" => "error", "code" => "server_error", "message" => "boom"))

      expect { chat.ask("q") }.to raise_error(AhoyDashboard::LLM::Error, /boom/)
    end
  end

  describe "the tool loop" do
    it "passes the reasoning and the call back with the result, and treats a null argument as left out" do
      stub_llm_replies(endpoint, streamed([ reasoning, call_item("call_1", '{"a":41,"unit":null}') ]), streamed([ message("42.") ]))

      answer = chat.with_tools(adder).ask("q")

      expect(answer.content).to eq("42.")
      input = llm_requests.last["input"]
      expect(input[1]).to eq(reasoning)
      expect(input[2]).to eq(call_item("call_1", '{"a":41,"unit":null}'))
      expect(input[3]).to eq("type" => "function_call_output", "call_id" => "call_1", "output" => '{"sum":42,"unit":"ones"}')
    end

    it "raises rather than running a call cut off by the output limit" do
      stub_llm_replies(endpoint, streamed([ call_item("call_1", '{"a":') ], status: "incomplete", incomplete: { "reason" => "max_output_tokens" }))

      expect { chat.with_tools(adder).ask("q") }.to raise_error(AhoyDashboard::LLM::TruncatedError)
    end

    it "asks the last round for words" do
      stub_llm_replies(endpoint, streamed([ call_item("call_1", '{"a":1,"unit":null}') ]))

      chat.with_tools(adder).ask("q")

      expect(llm_requests.size).to eq(AhoyDashboard::LLM::Chat::MAX_ROUNDS)
      expect(llm_requests.last["tool_choice"]).to eq("none")
    end
  end

  describe "history" do
    it "replays earlier tool calls as function calls with outputs saying the figures were not kept" do
      stub_llm_replies(endpoint, streamed([ message("ok") ]))

      built = chat.with_tools(adder)
      built.add_message(role: :user, content: "earlier")
      built.add_message(role: :assistant, content: "it was 42", tool_calls: [ { "name" => "adder", "arguments" => { "a" => 41 } } ])
      built.ask("and now?")

      input = llm_requests.first["input"]
      expect(input.map { |item| item["type"] || item["role"] }).to eq(%w[user function_call function_call_output assistant user])
      expect(input[1]).to include("name" => "adder", "arguments" => '{"a":41}')
      expect(input[2]).to eq("type" => "function_call_output", "call_id" => input[1]["call_id"],
                             "output" => AhoyDashboard::LLM::Chat::NOT_KEPT)
    end
  end
end
