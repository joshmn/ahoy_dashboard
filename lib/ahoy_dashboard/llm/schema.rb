module AhoyDashboard
  module LLM
    # The parameter block on a tool, turned into the JSON Schema an OpenAI shaped
    # `tools[].function.parameters` wants. Small on purpose: a tool that needs
    # more than a flat object of scalars is a tool that is doing too much.
    class Schema
      TYPES = %w[string integer number boolean array object].freeze

      attr_reader :required

      def initialize
        @properties = {}
        @required = []
      end

      TYPES.each do |type|
        define_method(type) do |name, description: nil, required: true, **extra|
          add(name, type, description: description, required: required, **extra)
        end
      end

      def names
        @properties.keys
      end

      def to_h
        { "type" => "object", "properties" => @properties, "required" => @required }
      end

      def to_closed_h
        closed(to_h)
      end

      def to_all_required_h
        all_required(to_closed_h)
      end

      private

      def add(name, type, description:, required:, **extra)
        key = name.to_s
        property = { "type" => type }
        property["description"] = description.to_s if description.present?
        extra.each { |option, value| property[option.to_s] = value }

        @properties[key] = property
        @required << key if required

        self
      end

      def all_required(node)
        case node
        when Hash
          copy = node.transform_values { |value| all_required(value) }
          return copy unless copy["type"] == "object" && copy["properties"].is_a?(Hash)

          optional = copy["properties"].keys - Array(copy["required"])
          optional.each { |key| copy["properties"][key] = nullable(copy["properties"][key]) }
          copy.merge("required" => copy["properties"].keys)
        when Array then node.map { |value| all_required(value) }
        else node
        end
      end

      def nullable(property)
        copy = property.merge("type" => (Array(property["type"]) + [ "null" ]).uniq)
        copy["enum"] = (property["enum"] + [ nil ]).uniq if property["enum"].is_a?(Array)
        copy
      end

      def closed(node)
        case node
        when Hash
          copy = node.transform_values { |value| closed(value) }
          copy["additionalProperties"] = false if copy["type"] == "object"
          copy
        when Array then node.map { |value| closed(value) }
        else node
        end
      end
    end
  end
end
