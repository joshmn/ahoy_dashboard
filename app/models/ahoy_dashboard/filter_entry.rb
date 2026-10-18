module AhoyDashboard
  class FilterEntry
    SLOT = /\A\d{1,6}\z/

    attr_reader :raw

    class << self
      def read(raw)
        raw.respond_to?(:key?) ? new(raw) : nil
      end

      def slot(value)
        text = value.to_s.strip

        text.match?(SLOT) ? text.to_i : nil
      end
    end

    def initialize(raw)
      @raw = raw
    end

    def field(name)
      raw[name.to_s] || raw[name.to_sym]
    end

    def dimension_key
      field(:dimension).to_s
    end

    def dimension
      Dimension.find_by_key(dimension_key)
    end

    def operator
      field(:operator).presence&.to_s
    end

    def value
      field(:value).to_s
    end

    def raw_group
      raw.key?(Filters::GROUP) ? raw[Filters::GROUP] : raw[Filters::GROUP.to_sym]
    end

    def group
      self.class.slot(raw_group)
    end

    def group_ok?
      raw_group.nil? || raw_group.to_s.match?(SLOT)
    end

    def block
      self.class.slot(field(:block)) || 0
    end
  end
end
