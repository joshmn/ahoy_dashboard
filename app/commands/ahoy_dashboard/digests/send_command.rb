module AhoyDashboard
  module Digests
    class SendCommand < AhoyDashboard::Command
      def initialize(period:, now: Time.current)
        @period = digests.period!(period)
        @now = now
      end

      def call
        return broadcast(:disabled) unless digests.enabled?

        digest = claim

        case start(digest)
        when :done then broadcast(:already_done, digest)
        when :busy then broadcast(:busy, digest)
        else deliver(digest)
        end
      end

      private

      attr_reader :period, :now

      def digests
        raise NotImplementedError
      end

      def record
        raise NotImplementedError
      end

      def query
        raise NotImplementedError
      end

      def counts(_result)
        raise NotImplementedError
      end

      def skip?(_result)
        false
      end

      def start(digest)
        digest.with_lock do
          next :done if digest.done?
          next :busy unless digest.claimable?

          digest.update!(status: :sending, error: nil)
          :ok
        end
      end

      def claim
        window = digests.last_window(period, now: now)

        begin
          record.find_or_create_by!(period: period, starts_on: window.starts_on) do |digest|
            digest.ends_on = window.ends_on
          end
        rescue ActiveRecord::RecordNotUnique
          record.find_by!(period: period, starts_on: window.starts_on)
        end
      end

      def deliver(digest)
        result = query.call(window: digest.window)
        return skip(digest) if skip?(result)

        digests.mailer.with(digest: digest, result: result, recipients: digests.recipients).digest.deliver_now
        digest.update!(status: :sent, sent_at: Time.current, error: nil, **counts(result))
        broadcast(:sent, digest)
      rescue StandardError => e
        digest.update_columns(status: record.statuses[:failed],
                              error: "#{e.class}: #{e.message}".first(255), updated_at: Time.current)
        broadcast(:failed, digest, e)
      end
    end
  end
end
