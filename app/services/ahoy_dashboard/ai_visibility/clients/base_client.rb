module AhoyDashboard
  module AiVisibility
    module Clients
      class BaseClient
        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 120
        MESSAGE_LENGTH = 200

        def initialize(api_key:, model:, transport: nil)
          @api_key = api_key
          @model = model
          @transport = transport || LLM::Transport.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        end

        def ask(_text)
          raise NotImplementedError
        end

        private

        attr_reader :api_key, :model, :transport

        def assistant_name
          raise(NotImplementedError)
        end

        def require_key!
          raise AuthError, "#{assistant_name} has no key" if api_key.blank?
        end

        def asking
          yield
        rescue LLM::Error => e
          raise failure(e)
        end

        def failure(error)
          return Error.new("#{assistant_name} request failed: #{error.message}") if error.status.nil?

          message = [ "#{assistant_name} returned #{error.status}", error.detail.to_s.squish.truncate(MESSAGE_LENGTH).presence ]
                    .compact.join(": ")

          case error.status
          when 401, 403 then AuthError.new(message)
          when 429 then QuotaError.new(message)
          else Error.new(message)
          end
        end

        def source(url, title)
          ReplySource.new(url: url.to_s, title: title.to_s.squish.presence)
        end

        def unique(sources)
          sources.select { |entry| entry.url.present? }.uniq(&:url)
        end
      end
    end
  end
end
