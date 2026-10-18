module AhoyDashboard
  module LLM
    class Client
      UNFINISHED = "the stream ended before the response finished".freeze

      def initialize(api_base:, api_key:, transport: nil)
        @api_base = api_base.to_s.chomp("/")
        @api_key = api_key.to_s
        @transport = transport || Transport.new
      end

      private

      attr_reader :api_base, :api_key, :transport

      def bearer
        { "Authorization" => (api_key.present? ? "Bearer #{api_key}" : nil) }
      end
    end
  end
end
