# frozen_string_literal: true

module AhoyDashboard
  class PreloadAssociationsService
    def self.call(records:, associations:)
      return if records.empty?

      if ActiveRecord.version >= Gem::Version.new("7.0")
        ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
      else
        ActiveRecord::Associations::Preloader.new.preload(records, associations)
      end
    end
  end
end
