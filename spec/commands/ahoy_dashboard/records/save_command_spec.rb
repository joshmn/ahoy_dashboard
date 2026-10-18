require "rails_helper"

RSpec.describe AhoyDashboard::Records::SaveCommand do
  def form(**values)
    AhoyDashboard::PageGroupForm.new({ name: "Blog", patterns: "/blog/*" }.merge(values))
  end

  it "saves the form onto the record and broadcasts ok" do
    record = AhoyDashboard::PageGroup.new

    events = described_class.call(record: record, form: form)

    expect(events[:ok]).to eq(record)
    expect(record.reload).to have_attributes(name: "Blog", patterns: [ "/blog/*" ])
  end

  it "broadcasts invalid with the form and writes nothing when the form refuses" do
    invalid = form(name: "  ")

    events = described_class.call(record: AhoyDashboard::PageGroup.new, form: invalid)

    expect(events[:invalid]).to eq(invalid)
    expect(invalid.errors.messages).to eq(name: [ "can't be blank" ])
    expect(AhoyDashboard::PageGroup.count).to be_zero
  end

  it "hands the record's own errors back on the form" do
    create(:dash_page_group, name: "Blog")
    submitted = form

    events = described_class.call(record: AhoyDashboard::PageGroup.new, form: submitted)

    expect(events[:invalid]).to eq(submitted)
    expect(submitted.errors.full_messages).to eq([ "Name has already been taken" ])
  end

  it "reads a lost race on the unique index as the form's duplicate error" do
    record = AhoyDashboard::PageGroup.new
    allow(record).to receive(:save).and_raise(ActiveRecord::RecordNotUnique, "duplicate key")
    submitted = form

    events = described_class.call(record: record, form: submitted)

    expect(events[:invalid]).to eq(submitted)
    expect(submitted.errors.full_messages).to eq([ "Name is already taken" ])
  end

  it "puts a new record at the end of the list when asked to" do
    create(:dash_page_group, position: 4)
    record = AhoyDashboard::PageGroup.new

    described_class.call(record: record, form: form, append: true)

    expect(record.reload.position).to eq(5)
  end

  it "leaves an existing record where it is" do
    record = create(:dash_page_group, position: 2)
    create(:dash_page_group, position: 7)

    described_class.call(record: record, form: form(name: "Renamed"), append: true)

    expect(record.reload).to have_attributes(name: "Renamed", position: 2)
  end
end
