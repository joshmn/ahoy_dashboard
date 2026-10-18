module AhoyDashboard
  class Place < AhoyDashboard::Record
    SEPARATOR = ",".freeze

    scope :ordered, -> { order(:depth, :label, :code) }
    scope :roots, -> { where(depth: 0) }
    scope :children_of, ->(code) { where(parent_code: code) }
    scope :in_country, ->(code) { where(country_code: code.to_s.downcase) }

    def self.ready?
      table_exists? && exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def self.built_at
      maximum(:synced_at)
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def self.for_location(place)
      return nil if place.nil?
      return roots.in_country(place.country_code).first if place.country?

      in_country(place.country_code).find_by(name: place.canonical_name)
    end

    def country?
      depth.zero?
    end

    def children?
      children_count.positive?
    end

    def parts
      name.split(SEPARATOR)
    end

    def to_param
      code.to_s
    end
  end
end
