module AssistantFixtures
  # Off in test, the same posture as search console and the serp tracking, so a
  # spec that wants a real turn has to say so.
  def assistant_enabled!(model: "test-model")
    allow(AhoyDashboard::Assistant).to receive_messages(available?: true, model_name: model)
  end

  def answer_double(content, input_tokens: 10, output_tokens: 20, truncated: false)
    instance_double(AhoyDashboard::LLM::Message, content: content, input_tokens: input_tokens,
                                                 output_tokens: output_tokens, truncated?: truncated,
                                                 cache_read_tokens: 0, cache_write_tokens: 0)
  end

  def assistant_answers(content, tool_calls: [], input_tokens: 10, output_tokens: 20, truncated: false)
    answer = answer_double(content, input_tokens: input_tokens, output_tokens: output_tokens, truncated: truncated)
    chat = instance_double(AhoyDashboard::LLM::Chat)

    allow(chat).to receive(:on_tool_call) { |&block| tool_calls.each(&block) }
    allow(chat).to receive(:add_message)
    allow(chat).to receive(:ask).and_return(answer)
    allow(AhoyDashboard::Assistant).to receive(:chat).and_return(chat)

    chat
  end

  # Answers in pieces, the way a real one does, so a spec can watch the half
  # written answer land on the row the page is reading.
  def assistant_streams(*chunks, tool_calls: [], input_tokens: 10, output_tokens: 20)
    answer = answer_double(chunks.join, input_tokens: input_tokens, output_tokens: output_tokens)
    chat = instance_double(AhoyDashboard::LLM::Chat)
    fired = nil

    allow(chat).to receive(:on_tool_call) { |&block| fired = block }
    allow(chat).to receive(:add_message)
    allow(chat).to receive(:ask) do |_question, &block|
      tool_calls.each { |call| fired&.call(call) }
      chunks.each { |text| block&.call(Struct.new(:content).new(text)) }
      answer
    end
    allow(AhoyDashboard::Assistant).to receive(:chat).and_return(chat)

    chat
  end

  def assistant_raises(error)
    chat = instance_double(AhoyDashboard::LLM::Chat)
    allow(chat).to receive(:on_tool_call)
    allow(chat).to receive(:add_message)
    allow(chat).to receive(:ask).and_raise(error)
    allow(AhoyDashboard::Assistant).to receive(:chat).and_return(chat)

    chat
  end

  def tool_call(name, arguments = {})
    Struct.new(:name, :arguments).new(name, arguments)
  end
end

RSpec.configure { |config| config.include AssistantFixtures }
