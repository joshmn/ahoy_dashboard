# frozen_string_literal: true

module AhoyDashboard
  class SearchConsoleSlicePresenter
    Slice = AhoyDashboard::SearchConsole::Slice

    attr_reader :slice

    def initialize(slice:, countries:, path:)
      @slice = slice
      @country_codes = countries
      @path = path
    end

    def device_label
      slice.device_label
    end

    def country_label
      slice.country_label
    end

    def device_items
      [ item(Slice::ALL_DEVICES, slice.device.nil?, device: nil) ] +
        Slice::DEVICES.map { |key, label| item(label, slice.device == key, device: key) }
    end

    def country_items
      [ item(Slice::ALL_COUNTRIES, slice.country.nil?, country: nil) ] +
        countries.map { |code| item(AhoyDashboard::SearchConsole::Countries.name(code), slice.country == code, country: code) }
    end

    private

    attr_reader :country_codes, :path

    def item(label, active, **overrides)
      { label: label, url: path.call(slice.with(**overrides).to_h), active: active }
    end

    def countries
      slice.country && country_codes.exclude?(slice.country) ? [slice.country, *country_codes] : country_codes
    end
  end
end
