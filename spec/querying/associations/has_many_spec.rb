# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "has many" do
  before do
    model "Author", as_of: true do
      has_many :books, temporal: true
    end
    model "Book", as_of: true
  end

  t = Time.parse("2000-01-01")

  context "when all tables have period columns" do
    before(:context) do
      as_of_table :authors
      as_of_table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_1_v1: {id: 1, period: t+1...t+3},
          author_1_v2: {id: 1, period: t+3...t+5},
          author_1_v3: {id: 1, period: t+5...nil},
          author_2_v1: {id: 2, period: t+2...t+4},
          author_2_v2: {id: 2, period: t+4...t+6},
          author_2_v3: {id: 2, period: t+6...nil}
        },
        "Book" => {
          book_v1: {id: 1, author_id: 1, period: t+2...t+4},
          book_v2: {id: 1, author_id: 1, period: t+4...t+7},
          book_v3: {id: 1, author_id: 2, period: t+7...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_1_v1, {books: []}],
          [author_1_v2, {books: []}],
          [author_1_v3, {books: []}],
          [author_2_v1, {books: [book_v3]}],
          [author_2_v2, {books: [book_v3]}],
          [author_2_v3, {books: [book_v3]}]
        ],
        t+1 => [
          [author_1_v1, {books: []}]
        ],
        t+2 => [
          [author_1_v1, {books: [book_v1]}],
          [author_2_v1, {books: []}]
        ],
        t+3 => [
          [author_1_v2, {books: [book_v1]}],
          [author_2_v1, {books: []}]
        ],
        t+4 => [
          [author_1_v2, {books: [book_v2]}],
          [author_2_v2, {books: []}]
        ],
        t+5 => [
          [author_1_v3, {books: [book_v2]}],
          [author_2_v2, {books: []}]
        ],
        t+6 => [
          [author_1_v3, {books: [book_v2]}],
          [author_2_v3, {books: []}]
        ],
        t+7 => [
          [author_1_v3, {books: []}],
          [author_2_v3, {books: [book_v3]}]
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

  context "when target table has no period column" do
    before(:context) do
      as_of_table :authors
      table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_1_v1: {id: 1, period: t+1...t+3},
          author_1_v2: {id: 1, period: t+3...nil}
        },
        "Book" => {
          foo: {id: 1, author_id: 1}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_1_v1, {books: [foo]}],
          [author_1_v2, {books: [foo]}]
        ],
        t+1 => [
          [author_1_v1, {books: [foo]}]
        ],
        t+2 => [
          [author_1_v1, {books: [foo]}]
        ],
        t+3 => [
          [author_1_v2, {books: [foo]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 4) { Author.eager_load(:books) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 4) { Author.preload(:books) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 4)
    end
  end

  context "when source table has no period column" do
    before(:context) do
      table :authors
      as_of_table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_bob: {id: 1},
          author_sam: {id: 2}
        },
        "Book" => {
          book_v1: {id: 1, author_id: 1, period: t+1...t+2},
          book_v2: {id: 1, author_id: 1, period: t+2...t+3},
          book_v3: {id: 1, author_id: 2, period: t+3...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_bob, {books: []}],
          [author_sam, {books: [book_v3]}]
        ],
        t+1 => [
          [author_bob, {books: [book_v1]}],
          [author_sam, {books: []}]
        ],
        t+2 => [
          [author_bob, {books: [book_v2]}],
          [author_sam, {books: []}]
        ],
        t+3 => [
          [author_bob, {books: []}],
          [author_sam, {books: [book_v3]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 4) { Author.eager_load(:books) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 4) { Author.preload(:books) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 4)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
