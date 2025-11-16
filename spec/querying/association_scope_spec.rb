# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe ActiveRecord::Temporal::Querying::AssociationScope do
  before do
    table :authors, primary_key: [:id, :version] do |t|
      t.bigint :id, null: false
      t.bigserial :version, null: false
      t.tstzrange :period
      t.string :name
    end
    table :books, primary_key: [:id, :version] do |t|
      t.bigint :id, null: false
      t.bigserial :version, null: false
      t.tstzrange :period
      t.string :name
      t.references :author
    end
    table :libraries do |t|
      t.string :name
    end

    model "Author", as_of: true do
      has_many :books, temporal: true
    end
    model "Book", as_of: true
    model "Library", as_of: true
  end

  after { drop_all_tables }

  t = Time.parse("2000-01-01")

  build_records do
    {
      "Author" => {
        author_bob_v1: {id: 1, name: "Bob", period: t+1...t+3},
        author_bob_v2: {id: 1, name: "Bob", period: t+3...t+5},
        author_bob_v3: {id: 1, name: "Bob", period: t+5...nil},
        author_sam_v1: {id: 2, name: "Sam", period: t+2...t+4},
        author_sam_v2: {id: 2, name: "Sam", period: t+4...t+6},
        author_sam_v3: {id: 2, name: "Sam", period: t+6...nil}
      },
      "Book" => {
        foo_v1: {id: 1, name: "Foo old", author_id: 1, period: t+2...t+4},
        foo_v2: {id: 1, name: "Foo new", author_id: 1, period: t+4...t+7},
        foo_v3: {id: 1, name: "Foo new", author_id: 2, period: t+7...nil}
      },
      "Library" => {
        author_bob: {name: "Bob"},
        author_sam: {name: "Sam"}
      }
    }
  end

  context "without a scope" do
    let(:timeline) do
      {
        nil => [
          [author_bob_v1, {books: []}],
          [author_bob_v2, {books: []}],
          [author_bob_v3, {books: []}],
          [author_sam_v1, {books: [foo_v3]}],
          [author_sam_v2, {books: [foo_v3]}],
          [author_sam_v3, {books: [foo_v3]}]
        ],
        t+1 => [
          [author_bob_v1, {books: []}]
        ],
        t+2 => [
          [author_bob_v1, {books: [foo_v1]}],
          [author_sam_v1, {books: []}]
        ],
        t+3 => [
          [author_bob_v2, {books: [foo_v1]}],
          [author_sam_v1, {books: []}]
        ],
        t+4 => [
          [author_bob_v2, {books: [foo_v2]}],
          [author_sam_v2, {books: []}]
        ],
        t+5 => [
          [author_bob_v3, {books: [foo_v2]}],
          [author_sam_v2, {books: []}]
        ],
        t+6 => [
          [author_bob_v3, {books: [foo_v2]}],
          [author_sam_v3, {books: []}]
        ],
        t+7 => [
          [author_bob_v3, {books: []}],
          [author_sam_v3, {books: [foo_v3]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 8) { Author.eager_load(:books) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 8) { Author.preload(:books) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 8)
    end
  end

  context "given a scope" do
    before do
      Author.class_eval do
        has_many :books,
          temporal_association_scope { where(name: "Foo old") }
      end
    end

    let(:timeline) do
      {
        nil => [
          [author_bob_v1, {books: []}],
          [author_bob_v2, {books: []}],
          [author_bob_v3, {books: []}],
          [author_sam_v1, {books: []}],
          [author_sam_v2, {books: []}],
          [author_sam_v3, {books: []}]
        ],
        t+1 => [
          [author_bob_v1, {books: []}]
        ],
        t+2 => [
          [author_bob_v1, {books: [foo_v1]}],
          [author_sam_v1, {books: []}]
        ],
        t+3 => [
          [author_bob_v2, {books: [foo_v1]}],
          [author_sam_v1, {books: []}]
        ],
        t+4 => [
          [author_bob_v2, {books: []}],
          [author_sam_v2, {books: []}]
        ],
        t+5 => [
          [author_bob_v3, {books: []}],
          [author_sam_v2, {books: []}]
        ],
        t+6 => [
          [author_bob_v3, {books: []}],
          [author_sam_v3, {books: []}]
        ],
        t+7 => [
          [author_bob_v3, {books: []}],
          [author_sam_v3, {books: []}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 8) { Author.eager_load(:books) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 8) { Author.preload(:books) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 8)
    end
  end

  context "given an instance-dependent scope" do
    before do
      Author.class_eval do
        has_many :books,
          temporal_association_scope { |owner|
            (owner.name == "Bob") ? where(name: "Foo new") : none
          }
      end
    end

    let(:timeline) do
      {
        nil => [
          [author_bob_v1, {books: []}],
          [author_bob_v2, {books: []}],
          [author_bob_v3, {books: []}],
          [author_sam_v1, {books: []}],
          [author_sam_v2, {books: []}],
          [author_sam_v3, {books: []}]
        ],
        t+1 => [
          [author_bob_v1, {books: []}]
        ],
        t+2 => [
          [author_bob_v1, {books: []}],
          [author_sam_v1, {books: []}]
        ],
        t+3 => [
          [author_bob_v2, {books: []}],
          [author_sam_v1, {books: []}]
        ],
        t+4 => [
          [author_bob_v2, {books: [foo_v2]}],
          [author_sam_v2, {books: []}]
        ],
        t+5 => [
          [author_bob_v3, {books: [foo_v2]}],
          [author_sam_v2, {books: []}]
        ],
        t+6 => [
          [author_bob_v3, {books: [foo_v2]}],
          [author_sam_v3, {books: []}]
        ],
        t+7 => [
          [author_bob_v3, {books: []}],
          [author_sam_v3, {books: []}]
        ]
      }
    end

    it "eager-loading raises an error" do
      expect { Author.as_of(t+3).eager_load(:books).load }
        .to raise_error(ArgumentError, /is instance dependent/)
    end

    describe "#preload" do
      test_eager_loading(n_steps: 8) { Author.preload(:books) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 8)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
