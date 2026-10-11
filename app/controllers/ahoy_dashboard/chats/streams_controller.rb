module AhoyDashboard
  module Chats
    class StreamsController < AhoyDashboard::BaseController
      requires_installed :assistant

      include ActionController::Live

      TICK = 0.5
      LIMIT = 120
      RETRY_MS = 3_000

      def show
        chat = AhoyDashboard::Chat.find(params[:chat_id])
        open_stream

        # The row is written by Sidekiq, in another process, and this loop asks the
        # same question a few hundred times. Said outright rather than left to
        # whatever the executor happened to hand this thread: a poll that reads
        # its own cached first answer would sit there showing what the page said
        # when it opened, and it is a query per tick either way.
        AhoyDashboard::ChatMessage.uncached { watch(chat) }
      rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
        nil
      ensure
        response.stream.close
      end

      private

      def open_stream
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache, no-store"
        response.headers["Connection"] = "keep-alive"
        response.headers["X-Accel-Buffering"] = "no"
        response.stream.write("retry: #{RETRY_MS}\n\n")
      end

      def watch(chat)
        started = Time.current

        loop do
          message = latest(chat)
          return finish(message) if message.nil? || !message.pending?

          revision = [ message.id, message.updated_at ]
          if revision != @last_revision
            send_event("tick", payload(message))
            @last_revision = revision
          end
          return finish(message) if Time.current - started > LIMIT

          sleep TICK
        end
      end

      def finish(message)
        send_event("done", payload(message))
      end

      def latest(chat)
        replies = chat.chat_messages.where(role: :assistant)
        return replies.find_by(id: params[:message_id]) if params[:message_id].present?

        replies.order(:created_at, :id).last
      end

      def payload(message)
        return { status: "gone", content: "", tools: [] } if message.nil?

        { status: message.status, content: message.content.to_s,
          tools: AhoyDashboard::ChatMessageDecorator.new(message).looked_at }
      end

      def send_event(name, data)
        response.stream.write("event: #{name}\ndata: #{data.to_json}\n\n")
      end
    end
  end
end
