# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe ActiveRecord::Temporal::Querying::ScopeRegistry do
  subject { described_class }

  t = Time.utc(2000)

  around do |example|
    travel_to current_time, &example
  end

  let(:current_time) { t+1601 }

  let(:registry) do
    described_class.new(
      global_constraints: {validity: t, system_period: t-1},
      association_constraints: {validity: t+1, system_period: t-2},
      association_tags: {validity: t+2, system_period: t-3}
    )
  end

  let(:empty_registry) { described_class.new }

  describe "::new", "attribute readers" do
    it "accepts constraints and tags" do
      new_registry = described_class.new(
        global_constraints: {validity: t},
        association_constraints: {validity: t+1},
        association_tags: {validity: t+2}
      )

      expect(new_registry).to have_attributes(
        global_constraints: {validity: t},
        association_constraints: {validity: t+1},
        association_tags: {validity: t+2}
      )
    end

    it "defaults to empty hashes" do
      new_registry = described_class.new

      expect(new_registry).to have_attributes(
        global_constraints: {},
        association_constraints: {},
        association_tags: {}
      )
    end
  end

  describe "attributes writers" do
    it "sets attributes" do
      registry.global_constraints = {validity: t+100}
      registry.association_constraints = {validity: t+101}
      registry.association_tags = {validity: t+102}

      expect(registry).to have_attributes(
        global_constraints: {validity: t+100},
        association_constraints: {validity: t+101},
        association_tags: {validity: t+102}
      )
    end
  end

  describe "#global_constraint_for" do
    it "returns the time of the dimension" do
      expect(registry.global_constraint_for(:validity)).to eq t
      expect(registry.global_constraint_for(:system_period)).to eq t-1
    end

    it "falls back on the universal global constraint time" do
      expect(empty_registry.global_constraint_for(:validity))
        .to be_nil

      empty_registry.universal_global_constraint_time = t+10

      expect(empty_registry.global_constraint_for(:validity))
        .to eq(t+10)

      empty_registry.set_global_constraints(validity: t+3)

      expect(empty_registry.global_constraint_for(:validity))
        .to eq(t+3)
    end
  end

  describe "#association_constraint_for" do
    it "returns the time of the dimension" do
      expect(registry.association_constraint_for(:validity)).to eq t+1
    end

    it "defaults to the global constraint and then the current time" do
      expect(empty_registry.association_constraint_for(:validity))
        .to eq(current_time)

      empty_registry.set_global_constraints(validity: t+1)

      expect(empty_registry.association_constraint_for(:validity))
        .to eq(t+1)

      empty_registry.set_global_constraints(validity: t+2)

      expect(empty_registry.association_constraint_for(:validity))
        .to eq(t+2)
    end
  end

  describe "#association_tag_for" do
    it "returns the time of the dimension" do
      expect(registry.association_tag_for(:validity)).to eq t+2
      expect(registry.association_tag_for(:system_period)).to eq t-3
    end
  end

  describe "#global_constraints_for" do
    it "returns the time of the dimension" do
      expect(registry.global_constraints_for(:validity))
        .to eq(validity: t)

      expect(registry.global_constraints_for(:validity, :system_period))
        .to eq(validity: t, system_period: t-1)
    end

    it "falls back on the universal global constraint time" do
      expect(empty_registry.global_constraints_for(:validity, :system_period))
        .to eq({})

      empty_registry.universal_global_constraint_time = t+10

      expect(empty_registry.global_constraints_for(:validity, :system_period))
        .to eq(validity: t+10, system_period: t+10)

      empty_registry.set_global_constraints(validity: t+3)

      expect(empty_registry.global_constraints_for(:validity, :system_period))
        .to eq(validity: t+3, system_period: t+10)
    end
  end

  describe "#association_constrains_for" do
    it "returns the time of the dimension" do
      expect(registry.association_constraints_for(:validity))
        .to eq(validity: t+1)

      expect(registry.association_constraints_for(:validity, :system_period))
        .to eq(validity: t+1, system_period: t-2)
    end

    it "defaults to the global constraint and then the current time" do
      expect(empty_registry.association_constraints_for(:validity, :system_period))
        .to eq(validity: current_time, system_period: current_time)

      empty_registry.set_global_constraints(validity: t+1)

      expect(empty_registry.association_constraints_for(:validity, :system_period))
        .to eq(validity: t+1, system_period: current_time)

      empty_registry.set_association_constraints(validity: t+2)

      expect(empty_registry.association_constraints_for(:validity, :system_period))
        .to eq(validity: t+2, system_period: current_time)
    end
  end

  describe "#association_tags_for" do
    it "returns the time of the dimension" do
      expect(registry.association_tags_for(:validity))
        .to eq(validity: t+2)
      expect(registry.association_tags_for(:validity, :system_period))
        .to eq(validity: t+2, system_period: t-3)
    end
  end

  describe "#set_<domain>_<type>_for" do
    it "updates" do
      registry.set_global_constraints(validity: t+100)
      registry.set_association_constraints(validity: t+101)
      registry.set_association_tags(validity: t+102)

      expect(registry).to have_attributes(
        global_constraints: {validity: t+100, system_period: t-1},
        association_constraints: {validity: t+101, system_period: t-2},
        association_tags: {validity: t+102, system_period: t-3}
      )
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
