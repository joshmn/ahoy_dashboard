module LLMFixtures
  def quiet_transport
    AhoyDashboard::LLM::Transport.new(sleeper: ->(_seconds) { })
  end

  def openai_frame(data)
    "event: #{data["type"]}\ndata: #{JSON.generate(data)}\n\n"
  end

  def anthropic_frame(type, payload = {})
    "event: #{type}\ndata: #{JSON.generate(payload.transform_keys(&:to_s).merge("type" => type))}\n\n"
  end

  def llm_requests
    @llm_requests ||= []
  end

  def llm_raw_requests
    @llm_raw_requests ||= []
  end

  def stub_llm_replies(endpoint, *bodies)
    queue = bodies.dup
    stub_request(:post, endpoint).to_return do |request|
      llm_raw_requests << request.body
      llm_requests << JSON.parse(request.body)
      { status: 200, body: queue.size > 1 ? queue.shift : queue.first }
    end
    llm_requests
  end
end

RSpec.configure { |config| config.include LLMFixtures }
