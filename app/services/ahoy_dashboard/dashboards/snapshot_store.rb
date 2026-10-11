# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class SnapshotStore
      class << self
        def read(key:)
          value = read_value(key: key)
          return unless value.is_a?(Hash) && value["payload"].is_a?(Hash)

          Snapshot.new(payload: value.fetch("payload"), computed_at: Time.iso8601(value.fetch("computed_at")))
        rescue KeyError, ArgumentError, TypeError
          nil
        end

        def write(key:, snapshot:)
          write_value(key: key, value: snapshot.to_cache, expires_in: Snapshot::MAX_AGE)
        end

        def read_value(key:)
          fresh_local_cache { AhoyDashboard.cache.read(key) }
        end

        def write_value(key:, value:, expires_in:)
          fresh_local_cache { AhoyDashboard.cache.write(key, value, expires_in: expires_in) }
        end

        def delete(key:)
          fresh_local_cache { AhoyDashboard.cache.delete(key) }
        end

        private

        def fresh_local_cache(&block)
          AhoyDashboard.cache.respond_to?(:with_local_cache) ? AhoyDashboard.cache.with_local_cache(&block) : block.call
        end
      end
    end
  end
end
