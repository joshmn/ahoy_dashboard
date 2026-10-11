module AhoyDashboard
  # One row of the gazetteer: somewhere a search can be run from. Built from the
  # provider's own published list, never written by hand.
  #
  # Nothing downstream depends on it. A keyword stores the place it searches from
  # as the string the adapters want, the same as it always has, so this table can
  # be empty, stale or dropped and every keyword on the list keeps working. It is
  # an input aid for the forms and nothing else.
  class Place < AhoyDashboard::Record
    SEPARATOR = ",".freeze

    scope :ordered, -> { order(:depth, :label, :code) }
    scope :roots, -> { where(depth: 0) }
    scope :children_of, ->(code) { where(parent_code: code) }
    scope :in_country, ->(code) { where(country_code: code.to_s.downcase) }
    scope :with_children, -> { where(arel_table[:children_count].gteq(1)) }

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

    def parent_path
      parts.drop(1).join(SEPARATOR)
    end

    def to_location
      return Serp::Location.country(country_code) if country?

      Serp::Location.city(canonical_name: name, country_code: country_code)
    end

    def to_param
      code.to_s
    end
  end
end
