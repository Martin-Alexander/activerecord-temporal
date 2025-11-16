# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe ActiveRecord::Temporal::Querying::Scoping do
  t = Time.utc(2000)

  around do |example|
    travel_to current_time, &example
  end

  let(:current_time) { t+1601 }

  before do
    ActiveSupport::IsolatedExecutionState[:temporal_querying_registry] = nil
  end

  let(:scope_registry) do
    ActiveRecord::Temporal::Querying::ScopeRegistry
  end

  describe "::at" do
    it "given a time it sets the universal global time for that block" do
      described_class.at t+10 do
        expect(scope_registry.global_constraint_for(:foo)).to eq t+10
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
    end

    it "given a hash it sets that dimension's global time for that block" do
      described_class.at foo: t+10 do
        expect(scope_registry.global_constraint_for(:foo)).to eq t+10
        expect(scope_registry.global_constraint_for(:bar)).to be_nil
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
      expect(scope_registry.global_constraint_for(:bar)).to be_nil
    end

    it "given multiple constraints it sets that dimension's global time for that block" do
      described_class.at foo: t+10, bar: t+2 do
        expect(scope_registry.global_constraint_for(:foo)).to eq t+10
        expect(scope_registry.global_constraint_for(:bar)).to eq t+2
        expect(scope_registry.global_constraint_for(:baz)).to be_nil
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
      expect(scope_registry.global_constraint_for(:bar)).to be_nil
      expect(scope_registry.global_constraint_for(:baz)).to be_nil
    end

    it "universal overrides constrains" do
      described_class.at foo: t+10 do
        expect(scope_registry.global_constraint_for(:foo)).to eq t+10

        described_class.at t+3 do
          expect(scope_registry.global_constraint_for(:foo)).to eq t+3
        end

        expect(scope_registry.global_constraint_for(:foo)).to eq t+10
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
    end

    it "is nestable" do
      described_class.at t+10 do
        described_class.at t+20 do
          expect(scope_registry.global_constraint_for(:foo)).to eq t+20
        end

        expect(scope_registry.global_constraint_for(:foo)).to eq t+10
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
    end

    it "reset original time if error occurs" do
      begin
        described_class.at t+10 do
          raises
        end
      rescue
      end

      expect(scope_registry.global_constraint_for(:foo)).to be_nil
    end
  end

  describe "::as_of" do
    it "sets that dimension's association tags and constraints" do
      described_class.as_of foo: t+10 do
        expect(scope_registry.association_constraint_for(:foo)).to eq t+10
        expect(scope_registry.association_tag_for(:foo)).to eq t+10
        expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
        expect(scope_registry.association_tag_for(:bar)).to be_nil
      end

      expect(scope_registry.association_constraint_for(:foo)).to eq(current_time)
      expect(scope_registry.association_tag_for(:foo)).to be_nil
      expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
      expect(scope_registry.association_tag_for(:bar)).to be_nil
    end

    it "given multiple time coords it sets that dimension's association tags and constraints" do
      described_class.as_of foo: t+10, bar: t+2 do
        expect(scope_registry.association_constraint_for(:foo)).to eq t+10
        expect(scope_registry.association_tag_for(:foo)).to eq t+10
        expect(scope_registry.association_constraint_for(:bar)).to eq t+2
        expect(scope_registry.association_tag_for(:bar)).to eq t+2
        expect(scope_registry.association_constraint_for(:baz)).to eq(current_time)
        expect(scope_registry.association_tag_for(:baz)).to be_nil
      end

      expect(scope_registry.association_constraint_for(:foo)).to eq(current_time)
      expect(scope_registry.association_tag_for(:foo)).to be_nil
      expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
      expect(scope_registry.association_tag_for(:bar)).to be_nil
      expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
      expect(scope_registry.association_tag_for(:bar)).to be_nil
    end

    it "is nestable and mergeable" do
      described_class.as_of foo: t+10 do
        described_class.as_of foo: t+50 do
          expect(scope_registry.association_constraint_for(:foo)).to eq t+50
          expect(scope_registry.association_tag_for(:foo)).to eq t+50
          expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
          expect(scope_registry.association_tag_for(:bar)).to be_nil
        end

        described_class.as_of bar: t+50 do
          expect(scope_registry.association_constraints_for(:foo, :bar))
            .to eq(foo: t+10, bar: t+50)
          expect(scope_registry.association_tags_for(:foo, :bar))
            .to eq(foo: t+10, bar: t+50)
        end

        expect(scope_registry.association_constraint_for(:foo)).to eq t+10
        expect(scope_registry.association_tag_for(:foo)).to eq t+10
        expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
        expect(scope_registry.association_tag_for(:bar)).to be_nil
      end

      expect(scope_registry.association_constraint_for(:foo)).to eq(current_time)
      expect(scope_registry.association_tag_for(:foo)).to be_nil
      expect(scope_registry.association_constraint_for(:bar)).to eq(current_time)
      expect(scope_registry.association_tag_for(:bar)).to be_nil
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
