require "rails_helper"

RSpec.describe AhoyDashboard::SecretBox do
  it "treats an encrypted JSON value that is not an object as empty credentials" do
    salt = described_class::CREDENTIAL_SALT
    envelope = described_class.write('["invalid"]', salt: salt)

    expect(described_class.read_values(value: envelope, salt: salt)).to eq({})
  end

  it "round trips a value" do
    expect(described_class.read(described_class.write("hello"))).to eq("hello")
  end

  it "does not leave the value readable in the envelope" do
    expect(described_class.write("hello")).not_to include("hello")
  end

  it "writes nothing for a blank value" do
    expect(described_class.write(nil)).to be_nil
    expect(described_class.write("")).to be_nil
  end

  it "reads nothing from a blank value" do
    expect(described_class.read(nil)).to be_nil
    expect(described_class.read("")).to be_nil
  end

  # A rotated secret_key_base has to read as "not connected" rather than raising
  # on every dashboard load. The fix for the operator is one reconnect click.
  it "hands back nil for an envelope it cannot open" do
    expect(described_class.read("not an envelope at all")).to be_nil
  end

  it "hands back nil for a tampered envelope" do
    envelope = described_class.write("hello")

    expect(described_class.read("#{envelope}x")).to be_nil
  end

  it "produces a different envelope each time for the same value" do
    expect(described_class.write("hello")).not_to eq(described_class.write("hello"))
  end
end
