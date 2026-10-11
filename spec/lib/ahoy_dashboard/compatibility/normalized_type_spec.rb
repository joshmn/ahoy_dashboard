# frozen_string_literal: true

require "rails_helper"

module AhoyDashboard

  module Spec

    class LegacyNormalizedRecord < ActiveRecord::Base
      self.abstract_class = true

      class << self
        undef_method(:normalizes) if method_defined?(:normalizes)
      end
    end

    class NormalizedProperty < LegacyNormalizedRecord
      extend AhoyDashboard::Compatibility::Record

      self.table_name = "ahoy_dashboard_properties"

      normalizes(:label, with: ->(value) { value.strip })
    end
  end
end

RSpec.describe AhoyDashboard::Compatibility::NormalizedType do
  let(:model) { AhoyDashboard::Spec::NormalizedProperty }

  it "normalizes assigned attributes" do
    record = model.new(key: "compat_normalization", label: "  Label  ")

    expect(record.label).to eq("Label")
  end

  it "normalizes lookup parameters" do
    record = model.create!(key: "compat_normalization", label: "Label")

    expect(model.find_by(label: "  Label  ")).to eq(record)
  end

  it "keeps nil unchanged unless explicitly requested" do
    expect(model.new(label: nil).label).to be_nil
  end

  it "normalizes nil when explicitly requested" do
    type = described_class.new(type: ActiveRecord::Type::String.new,
                               normalizer: ->(value) { value || "Default" }, normalize_nil: true)

    expect(type.cast(nil)).to eq("Default")
  end

  it "normalizes in-place changes before validation" do
    record = model.create!(key: "compat_normalization", label: "Label")
    record.label << "  "
    record.valid?

    expect(record.label).to eq("Label")
  end

  it "normalizes in-place changes when saving" do
    record = model.create!(key: "compat_normalization", label: "Label")
    record.label << "  "
    record.save!

    expect(record.reload.label).to eq("Label")
  end
end
