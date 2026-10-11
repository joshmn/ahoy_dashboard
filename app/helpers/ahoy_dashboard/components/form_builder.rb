module AhoyDashboard
  module Components
    class FormBuilder < ActionView::Helpers::FormBuilder
      TEXT_CONTROLS = %i[
        text_field email_field number_field url_field password_field search_field telephone_field
        date_field time_field datetime_local_field text_area
      ].freeze
      FIELD_KEYS = %i[label hint optional mono suffix append wrapper].freeze

      TEXT_CONTROLS.each do |name|
        define_method(name) do |method, options = {}|
          options = options.dup
          field = options.extract!(*FIELD_KEYS)
          control = super(method, control_options(method, options, field))
          field.key?(:label) ? wrap_field(method, control, id: options[:id], **field) : control
        end
      end

      def select(method, choices = nil, options = {}, html_options = {}, &block)
        html_options = html_options.dup
        field = html_options.extract!(*FIELD_KEYS)
        control = super(method, choices, options, control_options(method, html_options, field, base: "form-select"), &block)
        field.key?(:label) ? wrap_field(method, control, id: html_options[:id], **field) : control
      end

      def error_summary(heading = "That did not save.", unlinked: [])
        return if object.nil? || object.errors.empty?

        items = object.errors.messages.flat_map do |attribute, messages|
          messages.map do |message|
            text = attribute == :base || message.match?(/\A[[:upper:]]/) ? message : object.errors.full_message(attribute, message)
            if attribute == :base || unlinked.include?(attribute)
              @template.tag.li(text)
            else
              @template.tag.li(@template.link_to(text, "##{field_id(attribute)}", class: "alert-link"))
            end
          end
        end
        body = @template.safe_join([ @template.tag.p(heading, class: "alert-heading"), @template.tag.ul(@template.safe_join(items)) ])

        @template.tag.div(@template.tag.div(body, class: "alert-body"), class: "alert alert-danger", role: "alert")
      end

      def grid(&block)
        previous = @grid
        @grid = true
        @template.tag.div(@template.capture(&block), class: "row g-3")
      ensure
        @grid = previous
      end

      def field_id(method, *suffixes, namespace: @options[:namespace], index: @options[:index])
        return super if defined?(super)

        object_name = @object_name.to_s.gsub(/\]\[|[^-a-zA-Z0-9:.]/, "_").delete_suffix("_")
        [ namespace, object_name.presence, (index if object_name.present?), method.to_s.delete_suffix("?"), *suffixes ]
          .compact.join("_")
      end

      def fieldset(method, label:, hint: nil, optional: false, **options, &block)
        described = described_by(method, hint)
        parts = [
          @template.tag.legend(label_text(label, optional), class: "form-label"),
          @template.capture(&block),
          feedback(method),
          hint_tag(method, hint)
        ]
        classes = @template.class_names(options.delete(:class), "col-md-6" => @grid)

        @template.tag.fieldset(@template.safe_join(parts.compact), class: classes.presence, "aria-describedby": described, **options)
      end

      def segmented(method, choices, label:, hint: nil, size: nil, **options)
        fieldset(method, label: label, hint: hint, **options) do
          buttons = pairs(choices).flat_map do |value, text|
            [ radio_button(method, value, class: "btn-check"),
              self.label(method, text, value: value, class: @template.class_names("btn", "btn-sm" => size == :sm)) ]
          end
          @template.tag.div(@template.safe_join(buttons), class: @template.class_names("segmented", "segmented-sm" => size == :sm))
        end
      end

      def radio_group(method, choices, label:, hint: nil, **options)
        fieldset(method, label: label, hint: hint, **options) do
          @template.safe_join(pairs(choices).map do |value, text|
            @template.tag.div(@template.safe_join([ radio_button(method, value, class: "form-check-input"),
                                                    self.label(method, text, value: value, class: "form-check-label") ]),
                              class: "form-check")
          end)
        end
      end

      def check_boxes(method, collection, value_method, text_method, label:, hint: nil, detail: nil, **options)
        fieldset(method, label: label, hint: hint, **options) do
          collection_check_boxes(method, collection, value_method, text_method) do |item|
            text = item.text
            text = @template.safe_join([ text, " ", @template.tag.span(detail.call(item.object), class: "font-monospace text-body-tertiary") ]) if detail
            @template.tag.div(@template.safe_join([ item.check_box(class: "form-check-input"), item.label(class: "form-check-label") { text } ]),
                              class: "form-check")
          end
        end
      end

      def switch(method, label:, hint: nil, **options)
        check_field(method, label: label, hint: hint, switch: true, **options)
      end

      def check(method, label:, hint: nil, **options)
        check_field(method, label: label, hint: hint, switch: false, **options)
      end

      def actions(submit_label, cancel: nil, cancel_label: "Cancel", **options)
        parts = [
          submit(submit_label, class: @template.dash_button_class(tone: :primary, size: :md), **options),
          (@template.dash_button(cancel_label, cancel, tone: :link, size: :md) if cancel)
        ]

        @template.tag.div(@template.safe_join(parts.compact), class: "d-flex flex-wrap align-items-center gap-2 pt-1")
      end

      private

      def control_options(method, options, field, base: "form-control")
        errors = errors_for(method)
        described = [ options.delete(:"aria-describedby"), described_by(method, field[:hint]) ].compact.join(" ").presence

        options[:class] = @template.class_names(base, options[:class], "font-monospace" => field[:mono], "is-invalid" => errors.any?)
        options[:"aria-describedby"] = described if described
        options[:"aria-invalid"] = "true" if errors.any?
        options
      end

      def wrap_field(method, control, label:, id: nil, hint: nil, optional: false, suffix: nil, append: nil, mono: nil, wrapper: {})
        if suffix || append
          addons = [ control, (@template.tag.span(suffix, class: "input-group-text") if suffix), append ]
          control = @template.tag.div(@template.safe_join(addons.compact), class: "input-group")
        end

        parts = [
          self.label(method, label_text(label, optional), **{ class: "form-label", for: id }.compact),
          control,
          feedback(method),
          hint_tag(method, hint)
        ]

        wrapper = wrapper.dup
        classes = @template.class_names(wrapper.delete(:class), "col-md-6" => @grid)

        @template.tag.div(@template.safe_join(parts.compact), class: classes.presence, **wrapper)
      end

      def check_field(method, label:, hint:, switch:, **options)
        input_options = control_options(method, options, { hint: hint }, base: "form-check-input")
        input_options[:role] = "switch" if switch
        parts = [
          check_box(method, input_options),
          self.label(method, label, class: "form-check-label"),
          feedback(method),
          hint_tag(method, hint)
        ]

        @template.tag.div(@template.safe_join(parts.compact),
                          class: @template.class_names("form-check", "form-switch" => switch, "col-md-6" => @grid))
      end

      def label_text(text, optional)
        return text unless optional

        @template.safe_join([ text, " ", @template.tag.span("(optional)", class: "fw-normal text-body-tertiary") ])
      end

      def feedback(method)
        errors = errors_for(method)
        return if errors.empty?

        @template.tag.div(errors.to_sentence.upcase_first, id: field_id(method, :error), class: "invalid-feedback d-block")
      end

      def hint_tag(method, hint)
        @template.tag.div(hint, id: field_id(method, :hint), class: "form-text") if hint.present?
      end

      def described_by(method, hint)
        [ (field_id(method, :hint) if hint.present?), (field_id(method, :error) if errors_for(method).any?) ].compact.join(" ").presence
      end

      def errors_for(method)
        object.respond_to?(:errors) ? object.errors[method] : []
      end

      def pairs(choices)
        choices.map { |choice| choice.is_a?(Array) ? choice : [ choice, choice.to_s.humanize ] }
      end
    end
  end
end
