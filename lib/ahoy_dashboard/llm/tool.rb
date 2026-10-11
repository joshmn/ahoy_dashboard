module AhoyDashboard
  module LLM
    # What a tool has to look like. Subclasses declare a description and a
    # parameter block, and answer #execute with something that serialises.
    #
    # In lib rather than app, and required from the entrypoint, so the constant
    # exists before Zeitwerk autoloads anything that subclasses it. A base class
    # that is itself autoloaded is a NameError waiting for the first host whose
    # load order differs.
    class Tool
      class << self
        def desc(text = nil)
          @desc = text if text
          @desc.to_s
        end
        alias description desc

        def params(&block)
          @schema = Schema.new
          @schema.instance_eval(&block)
          @schema
        end

        def schema
          @schema ||= Schema.new
        end

        def tool_name
          name.to_s.demodulize.underscore
        end

        def to_function
          {
            "type" => "function",
            "function" => {
              "name" => tool_name,
              "description" => desc,
              "parameters" => schema.to_h
            }
          }
        end

        def to_open_ai(strict: false)
          {
            "type" => "function", "name" => tool_name, "description" => desc,
            "parameters" => strict ? schema.to_all_required_h : schema.to_closed_h, "strict" => strict
          }
        end

        def to_anthropic
          { "name" => tool_name, "description" => desc, "input_schema" => schema.to_closed_h }
        end
      end

      def name
        self.class.tool_name
      end

      def to_function
        self.class.to_function
      end

      def to_anthropic
        self.class.to_anthropic
      end

      def to_open_ai(strict: false)
        self.class.to_open_ai(strict: strict)
      end

      def execute(**)
        raise NotImplementedError, "#{self.class} must answer #execute"
      end
    end
  end
end
