module AhoyDashboard
  class ValueLabels
    class << self
      def register(key, &resolver)
        raise ArgumentError, "dashboard value labels for #{key.inspect} need a block" if resolver.nil?

        registry[key.to_s] = resolver
      end

      def registry
        @registry ||= {}
      end

      def registered?(key)
        registry.key?(key.to_s)
      end

      def for(key, values)
        resolver = registry[key.to_s]
        wanted = Array(values).map { |value| value.to_s.presence }.compact.uniq
        return {} if resolver.nil? || wanted.empty?

        resolver.call(wanted).map { |value, label| [ value.to_s, label.to_s.presence ] }.to_h.compact
      rescue StandardError => e
        Rails.logger.warn("dashboard value labels for #{key} failed: #{e.class}: #{e.message}")
        {}
      end
    end
  end
end
