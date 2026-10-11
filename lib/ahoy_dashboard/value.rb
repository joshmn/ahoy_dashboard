# frozen_string_literal: true

module AhoyDashboard

  class Value
    class << self
      def define(*attributes, &definition)
        names = attributes.map(&:to_sym)
        raise ArgumentError, "duplicate member" unless names.uniq == names

        Class.new(self).tap do |type|
          type.instance_variable_set(:@members, names.freeze)
          type.class_eval { attr_reader(*names) }
          type.class_eval(&definition) if definition
        end
      end

      def members
        @members.dup
      end

      def new(*values, **attributes)
        unless values.empty?
          raise ArgumentError, "cannot mix positional and keyword attributes" unless attributes.empty?
          raise ArgumentError, "wrong number of arguments" unless values.length == members.length

          attributes = members.zip(values).to_h
        end

        super(**attributes)
      end

      if RUBY_VERSION < "3.0"
        def new(*values)
          return super() if values.empty?

          if values.length == 1 && values.first.is_a?(Hash) &&
              (members.length != 1 || (values.first.keys & members).any?)
            return super(**values.first)
          end

          raise ArgumentError, "wrong number of arguments" unless values.length == members.length

          super(**members.zip(values).to_h)
        end
      end
    end

    def initialize(**attributes)
      missing = self.class.members - attributes.keys
      unknown = attributes.keys - self.class.members
      raise ArgumentError, "missing keywords: #{missing.join(', ')}" unless missing.empty?
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      attributes.each { |name, value| instance_variable_set("@#{name}", value) }
      freeze
    end

    def members
      self.class.members
    end

    def to_h
      self.class.members.each_with_object({}) do |name, attributes|
        pair = block_given? ? yield(name, public_send(name)) : [name, public_send(name)]
        attributes[pair.first] = pair.last
      end
    end

    def with(**attributes)
      return self if attributes.empty?

      self.class.new(**to_h.merge(attributes))
    end

    def ==(other)
      other.instance_of?(self.class) && to_h == other.to_h
    end

    def eql?(other)
      other.instance_of?(self.class) && to_h.eql?(other.to_h)
    end

    def hash
      [self.class, to_h].hash
    end

    def deconstruct
      self.class.members.map { |name| public_send(name) }
    end

    def deconstruct_keys(keys)
      return to_h unless keys

      to_h.select { |name, _value| keys.include?(name) }
    end
  end
end
