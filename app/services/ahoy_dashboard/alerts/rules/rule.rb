module AhoyDashboard
  module Alerts
    module Rules
      class Rule
        Finding = Data.define(:subject, :headline, :detail, :check_id, :previous_check_id, :reading, :sample_data) do
          def initialize(detail: nil, check_id: nil, previous_check_id: nil, reading: nil, sample_data: false, **rest)
            super
          end
        end

        class_attribute :definition, instance_writer: false
        class_attribute :latches, instance_writer: false, default: false

        def self.defines(**attributes)
          self.definition = Definition.new(rule: self, **attributes)
        end

        def self.latches!
          self.latches = true
        end

        def initialize(record, readings)
          @record = record
          @readings = readings
        end

        def findings
          []
        end

        def cleared
          []
        end

        private

        attr_reader :record, :readings

        def threshold
          record.threshold_value.to_i
        end

        def floor
          record.floor_value.to_i
        end

        def now
          readings.now
        end

        def finding(**attributes)
          Finding.new(**attributes)
        end

        def counted(count, word)
          "#{number(count)} #{word.pluralize(count)}"
        end

        def number(value)
          ActiveSupport::NumberHelper.number_to_delimited(value)
        end

        def day(date)
          date.strftime("%b %-d")
        end

        def local(time)
          time.in_time_zone(@zone ||= AhoyDashboard.time_zone)
        end

        def stamp(time)
          local(time).strftime("%b %-d, %-l:%M %p")
        end
      end
    end
  end
end
