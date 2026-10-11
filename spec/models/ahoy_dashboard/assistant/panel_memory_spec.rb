require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::PanelMemory do
  it "is shut and holds nothing when there is no cookie" do
    memory = described_class.read(nil)

    expect(memory).not_to be_open
    expect(memory.chat_id).to be_nil
  end

  it "reads back what it wrote" do
    memory = described_class.read(described_class.new(open: true, chat_id: 12).to_s)

    expect(memory).to be_open
    expect(memory.chat_id).to eq("12")
  end

  it "remembers the conversation while shut" do
    memory = described_class.read(described_class.new(open: false, chat_id: 12).to_s)

    expect(memory).not_to be_open
    expect(memory.chat_id).to eq("12")
  end

  it "remembers being open with no conversation yet" do
    memory = described_class.read(described_class.new(open: true).to_s)

    expect(memory).to be_open
    expect(memory.chat_id).to be_nil
  end

  it "takes nothing but digits as a conversation" do
    expect(described_class.read("open:12 or 1=1").chat_id).to be_nil
    expect(described_class.read("open:-4").chat_id).to be_nil
    expect(described_class.read("open:12:13").chat_id).to be_nil
  end

  it "reads anything it does not recognise as shut" do
    expect(described_class.read("wide open")).not_to be_open
    expect(described_class.read("OPEN:3")).not_to be_open
  end
end
