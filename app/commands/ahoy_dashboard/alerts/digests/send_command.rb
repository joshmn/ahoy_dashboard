module AhoyDashboard
  module Alerts
    module Digests
      class SendCommand < AhoyDashboard::Digests::SendCommand
        private

        def digests
          Digests
        end

        def record
          AhoyDashboard::AlertDigest
        end

        def query
          DigestQuery
        end

        def counts(result)
          { alerts_count: result.total }
        end

        def skip?(result)
          result.empty? && !Digests.send_empty?
        end

        def skip(digest)
          digest.update!(status: :skipped, alerts_count: 0, error: nil)
          broadcast(:skipped, digest)
        end
      end
    end
  end
end
