module AhoyDashboard
  # What a recorded value means, when the value on its own does not say it.
  #
  # A custom property holding a facility id is the case this exists for: the card
  # ranks 412 above 118, which is accurate and unreadable, and the dashboard has
  # never heard of a facility. So the host app registers the lookup the same way
  # it registers a dimension, from an initializer, and gets its own names back on
  # the card, in the details modal, in Explore, in the CSV and in an answer the
  # assistant writes.
  #
  # Registered per dimension key, and handed every value on the page at once
  # rather than one at a time, because nine rows have to cost one query and not
  # nine. Only the label moves: the raw value is what every filter link is built
  # from, so a row still filters to what was actually recorded.
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

      # Anything the resolver does not answer for keeps the value it was recorded
      # with. A row for a record somebody has since deleted still has to draw,
      # and the id is the most honest thing left to draw it with.
      #
      # A resolver that raises is a bad lookup in a host app, not a reason the
      # dashboard should stop rendering, so it is logged and the raw values
      # stand.
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
