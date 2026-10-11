# frozen_string_literal: true

module AhoyDashboard

  module Compatibility

    module Record
      def normalizes(*names, with:, apply_to_nil: false)
        return super if defined?(super)

        names.each do |name|
          decorate_dashboard_attribute(name: name, decorator: :normalization) do |type|
            NormalizedType.new(type: type, normalizer: with, normalize_nil: apply_to_nil)
          end
        end
        before_validation do
          names.each { |name| self[name] = self[name] if attribute_changed_in_place?(name) }
        end
      end

      def enum(name, values, **options)
        return super if ActiveRecord.gem_version >= Gem::Version.new("7.1")

        validation = options.delete(:validate)
        if ActiveRecord.gem_version >= Gem::Version.new("7.0")
          super(name, values, **options)
        else
          legacy = { name => values }
          options.each { |key, value| legacy["_#{key}".to_sym] = value }
          super(legacy)
        end
        return unless validation

        mapping = defined_enums.fetch(name.to_s)
        decorate_dashboard_attribute(name: name, decorator: :enum) do |type|
          subtype = type.is_a?(ActiveRecord::Enum::EnumType) ? type.send(:subtype) : type
          EnumType.new(name.to_s, mapping, subtype)
        end
        validation_options = validation.is_a?(Hash) ? validation : {}
        validates(name, inclusion: { in: mapping.keys }.merge(validation_options))
      end

      def upsert_all(rows, **options)
        return super if ActiveRecord.gem_version >= Gem::Version.new("7.0")

        Upsert.new(model: self, rows: rows, **options).call
      end

      private

      def decorate_dashboard_attribute(name:, decorator:, &block)
        if respond_to?(:decorate_attributes, true)
          decorate_attributes([name]) { |_attribute, type| block.call(type) }
        elsif ActiveRecord.gem_version >= Gem::Version.new("6.1")
          attribute(name, &block)
        else
          decorate_attribute_type(name, decorator, &block)
        end
      end
    end
  end
end
