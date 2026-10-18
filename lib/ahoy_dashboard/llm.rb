module AhoyDashboard
  module LLM
    class Error < StandardError
      attr_reader :status, :type, :detail

      def initialize(message = nil, status: nil, type: nil, detail: nil)
        @status = status
        @type = type
        @detail = detail
        super(message)
      end
    end

    class RefusedError < Error
      attr_reader :category

      def initialize(message = "the model declined to answer", category: nil)
        @category = category
        super(message)
      end
    end

    class TruncatedError < Error; end
  end
end

require "ahoy_dashboard/llm/schema"
require "ahoy_dashboard/llm/tool"
require "ahoy_dashboard/llm/message"
require "ahoy_dashboard/llm/transport"
require "ahoy_dashboard/llm/client"
require "ahoy_dashboard/llm/chat"
require "ahoy_dashboard/llm/anthropic/models"
require "ahoy_dashboard/llm/anthropic/client"
require "ahoy_dashboard/llm/anthropic/chat"
require "ahoy_dashboard/llm/open_ai/models"
require "ahoy_dashboard/llm/open_ai/output"
require "ahoy_dashboard/llm/open_ai/client"
require "ahoy_dashboard/llm/open_ai/chat"
require "ahoy_dashboard/llm/compatible/client"
require "ahoy_dashboard/llm/compatible/chat"
require "ahoy_dashboard/llm/context"
