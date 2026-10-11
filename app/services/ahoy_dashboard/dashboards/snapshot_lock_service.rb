# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotLockService
      class << self
        def call(key:, wait: true)
          identifier = Digest::SHA256.hexdigest(key)[0, 16].to_i(16) % (2**63)
          Record.connection_pool.with_connection do |connection|
            connection.transaction(requires_new: true) do
              function = wait ? "pg_advisory_xact_lock" : "pg_try_advisory_xact_lock"
              cast = wait ? "::text" : ""
              acquired = Record.uncached { connection.select_value("SELECT #{function}(#{identifier})#{cast}") }
              yield if wait || acquired
            end
          end
        end
      end
    end
  end
end
