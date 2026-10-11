module AhoyDashboard
  module Reports
    module Digests
      class SendCommand < AhoyDashboard::Command
        def initialize(period:, now: Time.current)
          @period = Digests.period!(period)
          @now = now
        end

        def call
          return broadcast(:disabled) unless Digests.enabled?

          digest = claim

          case start(digest)
          when :done then broadcast(:already_done, digest)
          when :busy then broadcast(:busy, digest)
          else deliver(digest)
          end
        end

        private

        attr_reader :period, :now

        # The row lock is held only long enough to put the digest in sending, and
        # everything expensive happens after it is let go. The query behind the
        # email runs async, and an async query inside a transaction raises. Handing
        # the mail to the delivery method inside one would hold the lock open
        # across a network call too.
        def start(digest)
          digest.with_lock do
            next :done if digest.done?
            next :busy unless digest.claimable?

            digest.update!(status: :sending, error: nil)
            :ok
          end
        end

        def claim
          window = Digests.last_window(period, now: now)

          begin
            AhoyDashboard::ReportDigest.find_or_create_by!(period: period, starts_on: window.starts_on) do |digest|
              digest.ends_on = window.ends_on
            end
          rescue ActiveRecord::RecordNotUnique
            AhoyDashboard::ReportDigest.find_by!(period: period, starts_on: window.starts_on)
          end
        end

        # The result is handed to the mailer rather than looked up again inside it.
        # It is eight aggregates and three breakdowns over two ranges, and reading
        # it twice to print it once is the kind of thing nobody notices until the
        # visits table is large.
        def deliver(digest)
          result = DigestQuery.call(window: digest.window)

          Digests.mailer.with(digest: digest, result: result, recipients: Digests.recipients).digest.deliver_now
          digest.update!(status: :sent, sent_at: Time.current, visitors_count: result.visitors, error: nil)
          broadcast(:sent, digest)
        rescue StandardError => e
          digest.update_columns(status: AhoyDashboard::ReportDigest.statuses[:failed],
                                error: "#{e.class}: #{e.message}".first(255), updated_at: Time.current)
          broadcast(:failed, digest, e)
        end
      end
    end
  end
end
