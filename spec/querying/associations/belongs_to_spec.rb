# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "belongs to" do
  before do
    model "Author", as_of: true
    model "Book", as_of: true do
      belongs_to :author, temporal: true
    end
  end

  t = Time.parse("2000-01-01")

  context "when target and source tables both have period columns" do
    before(:context) do
      as_of_table :authors
      as_of_table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Book" => {
          book_1_v1: {id: 100, author_id: nil, period: t+1...t+3},
          book_1_v2: {id: 100, author_id: 100, period: t+3...t+5},
          book_2_v1: {id: 200, author_id: 200, period: t+4...t+6},
          book_2_v2: {id: 200, author_id: 200, period: t+6...nil}
        },
        "Author" => {
          author_1_v1: {id: 100, period: t+2...nil},
          author_2_v1: {id: 200, period: t+2...t+4},
          author_2_v2: {id: 200, period: t+4...t+6},
          author_2_v3: {id: 200, period: t+6...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [book_1_v1, {author: nil}],
          [book_1_v2, {author: author_1_v1}],
          [book_2_v1, {author: author_2_v3}],
          [book_2_v2, {author: author_2_v3}]
        ],
        t+1 => [
          [book_1_v1, {author: nil}]
        ],
        t+2 => [
          [book_1_v1, {author: nil}]
        ],
        t+3 => [
          [book_1_v2, {author: author_1_v1}]
        ],
        t+4 => [
          [book_1_v2, {author: author_1_v1}],
          [book_2_v1, {author: author_2_v2}]
        ],
        t+5 => [
          [book_2_v1, {author: author_2_v2}]
        ],
        t+6 => [
          [book_2_v2, {author: author_2_v3}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 7) { Book.eager_load(:author) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 7) { Book.preload(:author) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 7)
    end
  end

  context "when target table has no period column" do
    before(:context) do
      table :authors
      as_of_table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Book" => {
          book_1_v1: {id: 100, author_id: nil, period: t+1...t+3},
          book_1_v2: {id: 100, author_id: 100, period: t+3...t+5},
          book_2_v1: {id: 200, author_id: 200, period: t+4...t+6},
          book_2_v2: {id: 200, author_id: 200, period: t+6...nil}
        },
        "Author" => {
          author_1: {id: 100},
          author_2: {id: 200}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [book_1_v1, {author: nil}],
          [book_1_v2, {author: author_1}],
          [book_2_v1, {author: author_2}],
          [book_2_v2, {author: author_2}]
        ],
        t+1 => [
          [book_1_v1, {author: nil}]
        ],
        t+2 => [
          [book_1_v1, {author: nil}]
        ],
        t+3 => [
          [book_1_v2, {author: author_1}]
        ],
        t+4 => [
          [book_1_v2, {author: author_1}],
          [book_2_v1, {author: author_2}]
        ],
        t+5 => [
          [book_2_v1, {author: author_2}]
        ],
        t+6 => [
          [book_2_v2, {author: author_2}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 7) { Book.eager_load(:author) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 7) { Book.preload(:author) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 7)
    end
  end

  context "when source table has no period column" do
    before(:context) do
      as_of_table :authors
      table :books do |t|
        t.references :author
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Book" => {
          book_1: {id: 100, author_id: nil},
          book_2: {id: 200, author_id: 200}
        },
        "Author" => {
          author_1_v1: {id: 100, period: t+2...nil},
          author_2_v1: {id: 200, period: t+2...t+4},
          author_2_v2: {id: 200, period: t+4...t+6},
          author_2_v3: {id: 200, period: t+6...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v3}]
        ],
        t+1 => [
          [book_1, {author: nil}],
          [book_2, {author: nil}]
        ],
        t+2 => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v1}]
        ],
        t+3 => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v1}]
        ],
        t+4 => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v2}]
        ],
        t+5 => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v2}]
        ],
        t+6 => [
          [book_1, {author: nil}],
          [book_2, {author: author_2_v3}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 7) { Book.eager_load(:author) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 7) { Book.preload(:author) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 7)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
