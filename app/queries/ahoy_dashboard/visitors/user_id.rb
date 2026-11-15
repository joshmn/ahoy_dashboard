module AhoyDashboard
  module Visitors
    module UserId
      COLUMN = "user_id".freeze
      LABELS = "user_id".freeze
      MAX_LENGTH = 255
      MAX_INTEGER = (2**63) - 1
      INTEGER = /\A\d{1,19}\z/
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      class << self
        def visits?
          AhoyDashboard.visit.column_names.include?(COLUMN)
        end

        def events?
          AhoyDashboard.event.column_names.include?(COLUMN)
        end

        def cast(raw)
          value = raw.to_s.strip
          return nil if value.empty? || value.length > MAX_LENGTH || !visits?

          case AhoyDashboard.visit.columns_hash[COLUMN].type
          when :integer
            value if value.match?(INTEGER) && value.to_i <= MAX_INTEGER
          when :uuid
            value.downcase if value.match?(UUID)
          else
            value
          end
        end

        def labels(values)
          AhoyDashboard::ValueLabels.for(LABELS, values)
        end
      end
    end
  end
end
