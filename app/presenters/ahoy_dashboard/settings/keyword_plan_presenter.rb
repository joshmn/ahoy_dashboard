module AhoyDashboard
  module Settings
    class KeywordPlanPresenter
      MONTH = 30.days

      FREQUENCY_LABELS = SerpKeywordDecorator::FREQUENCY_LABELS

      # A row is the two fields the form posts plus, when the gazetteer is on,
      # the catalogue row behind them. The catalogue is what lets the picker
      # open where the place already is, and what lets adding another place
      # start one level up from the last one.
      Row = Data.define(:country, :city, :place) do
        def picked?
          country.present?
        end

        def code
          place&.code
        end

        def parent_code
          place&.parent_code
        end

        def parent_label
          place&.parent_readable
        end

        def label
          place&.readable || city.presence || nil
        end
      end

      attr_reader :form, :suggestions

      def initialize(form:, suggestions: [])
        @form = form
        @suggestions = suggestions
      end

      def adapter_class
        @adapter_class ||= Serp.adapter_class
      end

      def provider_label
        Display.adapter_label(adapter_class)
      end

      def tracking_on?
        Serp.enabled?
      end

      def free?
        adapter_class.cost_units(pages: 1).zero?
      end

      def capped?
        !free? && provider&.capped? ? true : false
      end

      def cap
        provider.monthly_cap_units
      end

      def remaining
        provider.remaining_units
      end

      def over_cap?
        capped? && monthly > remaining
      end

      def countries
        names = adapter_class.countries || Serp::Location.country_names
        kept = rows.map(&:country).select(&:present?).reject { |code| names.key?(code) }

        names.merge(kept.index_with { |code| Serp::Location.country(code).country_name })
          .sort_by { |_code, name| name }
          .map { |code, name| [ name, code ] }
      end

      def rows
        @rows ||= begin
          filled = places.first(SerpKeyword::MAX_LOCATIONS).map do |place|
            Row.new(country: place.country_code.downcase, city: place.canonical_name.to_s,
                    place: catalogue[place.value])
          end

          blank = Row.new(country: "", city: "", place: nil)

          filled + Array.new(SerpKeyword::MAX_LOCATIONS - filled.size) { blank }
        end
      end

      # The picker is on only when there is something to pick from. Off, or
      # never built, and the forms keep the country select and the typed city,
      # which is the whole of what this replaces.
      def picker?
        Places.ready?
      end

      def picker_hint?
        Places.enabled? && !Places.ready?
      end

      def picker_off_reason
        return "The place list is not installed, so places are typed in for now." unless Places.installed?

        "The place list is off, so places are typed in." unless Places.enabled?
      end

      def places
        @places ||= form.location_values.map { |value| Serp::Location.parse(value) }
      end

      def pages
        form.pages.to_i.clamp(1, Serp::MAX_PAGES)
      end

      def frequency
        SerpKeyword::DURATIONS.key?(form.frequency.to_s) ? form.frequency.to_s : "weekly"
      end

      def per_check
        adapter_class.cost_units(pages: pages) * places.size
      end

      def monthly
        (per_check * checks_ratio).ceil
      end

      def monthly_checks
        (places.size * pages * checks_ratio).ceil
      end

      def batch_size
        form.queries.size
      end

      def batch_monthly
        monthly * batch_size
      end

      def batch_checks
        monthly_checks * batch_size
      end

      def batch_over_cap?
        capped? && batch_monthly > remaining
      end

      def costs
        (1..Serp::MAX_PAGES).map { |count| [ count, adapter_class.cost_units(pages: count) ] }.to_h
      end

      def durations
        SerpKeyword::DURATIONS.transform_values(&:to_i)
      end

      def where_label
        places.map { |place| place.city? ? place.canonical_name.to_s.split(",").first.to_s.strip : place.country_name }
          .to_sentence
      end

      def device_label
        form.device.to_s.humanize
      end

      def often_label
        "#{FREQUENCY_LABELS.fetch(frequency)}, top #{pages * Serp::RESULTS_PER_PAGE}"
      end

      private

      def catalogue
        @catalogue ||= picker? ? places.map { |place| [ place.value, decorate(Place.for_location(place)) ] }.to_h : {}
      end

      def decorate(place)
        place && PlaceDecorator.new(place)
      end

      def provider
        Serp.record
      end

      def checks_ratio
        MONTH.to_f / SerpKeyword::DURATIONS.fetch(frequency).to_i
      end
    end
  end
end
