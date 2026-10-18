module AhoyDashboard
  module Secrets
    class RemoveCommand < AhoyDashboard::Command
      def initialize(record:, key:)
        @record = record
        @key = key.to_sym
      end

      def call
        return broadcast(:missing) if record.nil? || record.credential(key).blank?

        record.update!(credentials: record.credentials.except(key))
        broadcast(:ok, record)
      end

      private

      attr_reader :record, :key
    end
  end
end
