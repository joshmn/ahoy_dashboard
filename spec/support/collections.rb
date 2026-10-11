# frozen_string_literal: true

module SpecCollections

  def sole_item(collection)
    items = collection.respond_to?(:limit) ? collection.limit(2).to_a : collection.to_a
    raise ArgumentError, "Expected one item, found #{items.size}" unless items.size == 1

    items.first
  end
end
