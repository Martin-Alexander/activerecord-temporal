# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe ActiveRecord::Temporal::Querying::AssociationMacros do
  after { drop_all_tables }

  shared_examples "accepts temporal option" do
    it "accepts :temporal option" do
      model "Foo", as_of: true
      model "Bar", as_of: true
      model "Baz", as_of: true
      model "Boo", as_of: true
      model "Moo"

      Foo.send(subject, :bar, temporal: true)
      Foo.send(subject, :baz, temporal: false)
      Foo.send(subject, :boo)
      Foo.send(subject, :moo, temporal: true)

      expect(Foo.reflect_on_association(:bar))
        .to have_attributes(klass: Bar, scope: be_present)

      expect(Foo.reflect_on_association(:baz))
        .to have_attributes(klass: Baz, scope: be_nil)

      expect(Foo.reflect_on_association(:boo))
        .to have_attributes(klass: Boo, scope: be_nil)

      expect(Foo.reflect_on_association(:moo))
        .to have_attributes(klass: Moo, scope: be_present)
    end
  end

  describe "#has_many" do
    subject { :has_many }

    include_examples "accepts temporal option"
  end

  describe "#belongs_to" do
    subject { :belongs_to }

    include_examples "accepts temporal option"
  end

  describe "#has_one" do
    subject { :has_one }

    include_examples "accepts temporal option"
  end

  describe "#has_and_belongs_to_many" do
    subject { :has_and_belongs_to_many }

    include_examples "accepts temporal option"
  end

  it "applies the temporal scope to association" do
    t = Time.utc(2000)

    conn.create_table :foos do |t|
      t.tstzrange :period, null: false
    end

    conn.create_table :bars do |t|
      t.tstzrange :period, null: false
      t.references :foo
    end

    model "Foo", as_of: true do
      has_many :bars, temporal: true
    end

    model "Bar", as_of: true do
      belongs_to :foo, temporal: true
    end

    foo = Foo.create!(period: t...t+5)
    foo.bars.create(period: t...t+3)
    foo.bars.create(period: t+2...t+5)

    expect(Foo.as_of(t+1).first.bars.count).to eq(1)
    expect(Foo.as_of(t+2).first.bars.count).to eq(2)
    expect(Foo.as_of(t+4).first.bars.count).to eq(1)

    expect(Bar.as_of(t+1).first.foo.time_tag).to eq(t+1)
  end
end

# rubocop:enable Layout/SpaceAroundOperators
