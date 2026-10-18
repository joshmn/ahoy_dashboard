# frozen_string_literal: true

module AhoyDashboard
  module Compatibility
    module ClassNames
      def class_names(*values)
        return super if defined?(super)

        tokens = dash_class_tokens(values).flat_map { |value| CGI.unescape_html(value).split(/\s+/) }
        safe_join(tokens.uniq, " ")
      end

      def dash_class_tokens(values)
        values.each_with_object([]) do |value, tokens|
          case value
          when Hash
            value.each { |name, enabled| tokens << name.to_s if enabled && name.present? }
          when Array
            tokens.concat(dash_class_tokens(value))
          else
            tokens << value.to_s if value.present?
          end
        end
      end
      private :dash_class_tokens

    end
  end
end
