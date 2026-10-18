module AhoyDashboard
  module Reports
    module Digests
      class SendCommand < AhoyDashboard::Digests::SendCommand
        private

        def digests
          Digests
        end

        def record
          AhoyDashboard::ReportDigest
        end

        def query
          DigestQuery
        end

        def counts(result)
          { visitors_count: result.visitors }
        end
      end
    end
  end
end
