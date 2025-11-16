# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "has many through" do
  before do
    model "Author", as_of: true do
      has_many :books, temporal: true
      has_many :publishers, temporal: true, through: :books
    end
    model "Book", as_of: true do
      belongs_to :publisher, temporal: true
    end
    model "Publisher", as_of: true
  end

  t = Time.parse("2000-01-01")

  context "when all tables have period columns" do
    before(:context) do
      as_of_table :authors
      as_of_table :publishers
      as_of_table :books do |t|
        t.references :author
        t.references :publisher
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_v1: {id: 100, period: t+1...t+4},
          author_v2: {id: 100, period: t+4...nil}
        },
        "Book" => {
          book_1_v1: {id: 100, author_id: 100, publisher_id: 100, period: t+2...t+3},
          book_1_v2: {id: 100, author_id: 100, publisher_id: 101, period: t+3...nil},
          book_2_v1: {id: 101, author_id: 100, publisher_id: 101, period: t+4...nil}
        },
        "Publisher" => {
          publisher_1_v1: {id: 100, period: t+1...t+4},
          publisher_2_v1: {id: 101, period: t+3...t+5},
          publisher_2_v2: {id: 101, period: t+5...nil}

        }
      }
    end

    shared_context "non-distinct timeline" do
      let(:timeline) do
        {
          nil => [
            [author_v1, {publishers: [publisher_2_v2, publisher_2_v2]}],
            [author_v2, {publishers: [publisher_2_v2, publisher_2_v2]}]
          ],
          t+1 => [[author_v1, {publishers: []}]],
          t+2 => [[author_v1, {publishers: [publisher_1_v1]}]],
          t+3 => [[author_v1, {publishers: [publisher_2_v1]}]],
          t+4 => [[author_v2, {publishers: [publisher_2_v1, publisher_2_v1]}]],
          t+5 => [[author_v2, {publishers: [publisher_2_v2, publisher_2_v2]}]]
        }
      end
    end

    shared_context "distinct timeline" do
      let(:timeline) do
        {
          nil => [
            [author_v1, {publishers: [publisher_2_v2]}],
            [author_v2, {publishers: [publisher_2_v2]}]
          ],
          t+1 => [[author_v1, {publishers: []}]],
          t+2 => [[author_v1, {publishers: [publisher_1_v1]}]],
          t+3 => [[author_v1, {publishers: [publisher_2_v1]}]],
          t+4 => [[author_v2, {publishers: [publisher_2_v1]}]],
          t+5 => [[author_v2, {publishers: [publisher_2_v2]}]]
        }
      end
    end

    describe "#eager_load" do
      include_context "distinct timeline"

      test_eager_loading(n_steps: 6) { Author.eager_load(:publishers) }
    end

    describe "#preload" do
      include_context "non-distinct timeline"

      test_eager_loading(n_steps: 6) { Author.preload(:publishers) }
    end

    describe "association reader" do
      include_context "non-distinct timeline"

      test_association_reader(n_steps: 6)
    end
  end

  context "when through table has no period column" do
    before(:context) do
      as_of_table :authors
      as_of_table :publishers
      table :books do |t|
        t.references :author
        t.references :publisher
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_v1: {id: 100, period: t+1...nil}
        },
        "Book" => {
          book_1: {id: 100, author_id: 100, publisher_id: 100},
          book_2: {id: 101, author_id: 100, publisher_id: 101}
        },
        "Publisher" => {
          publisher_1_v1: {id: 100, period: t+1...t+4},
          publisher_2_v1: {id: 101, period: t+3...t+5},
          publisher_2_v2: {id: 101, period: t+5...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [[author_v1, {publishers: [publisher_2_v2]}]],
        t+1 => [[author_v1, {publishers: [publisher_1_v1]}]],
        t+2 => [[author_v1, {publishers: [publisher_1_v1]}]],
        t+3 => [[author_v1, {publishers: [publisher_1_v1, publisher_2_v1]}]],
        t+4 => [[author_v1, {publishers: [publisher_2_v1]}]],
        t+5 => [[author_v1, {publishers: [publisher_2_v2]}]]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 6) { Author.eager_load(:publishers) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 6) { Author.preload(:publishers) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 6)
    end
  end

  context "when target table has no period column" do
    before(:context) do
      as_of_table :authors
      table :publishers
      as_of_table :books do |t|
        t.references :author
        t.references :publisher
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_v1: {id: 100, period: t+1...nil}
        },
        "Book" => {
          book_1_v1: {id: 100, author_id: 100, publisher_id: 100, period: t+2...t+3},
          book_1_v2: {id: 100, author_id: 100, publisher_id: 101, period: t+3...nil},
          book_2_v1: {id: 101, author_id: 100, publisher_id: 101, period: t+4...nil}
        },
        "Publisher" => {
          publisher_1: {id: 100},
          publisher_2: {id: 101}
        }
      }
    end

    shared_context "non-distinct timeline" do
      let(:timeline) do
        {
          nil => [[author_v1, {publishers: [publisher_2, publisher_2]}]],
          t+1 => [[author_v1, {publishers: []}]],
          t+2 => [[author_v1, {publishers: [publisher_1]}]],
          t+3 => [[author_v1, {publishers: [publisher_2]}]],
          t+4 => [[author_v1, {publishers: [publisher_2, publisher_2]}]],
          t+5 => [[author_v1, {publishers: [publisher_2, publisher_2]}]]
        }
      end
    end

    shared_context "distinct timeline" do
      let(:timeline) do
        {
          nil => [[author_v1, {publishers: [publisher_2]}]],
          t+1 => [[author_v1, {publishers: []}]],
          t+2 => [[author_v1, {publishers: [publisher_1]}]],
          t+3 => [[author_v1, {publishers: [publisher_2]}]],
          t+4 => [[author_v1, {publishers: [publisher_2]}]],
          t+5 => [[author_v1, {publishers: [publisher_2]}]]
        }
      end
    end

    describe "#eager_load" do
      include_context "distinct timeline"

      test_eager_loading(n_steps: 6) { Author.eager_load(:publishers) }
    end

    describe "#preload" do
      include_context "non-distinct timeline"

      test_eager_loading(n_steps: 6) { Author.preload(:publishers) }
    end

    describe "association reader" do
      include_context "non-distinct timeline"

      test_association_reader(n_steps: 6)
    end
  end

  context "when source table has no period column" do
    before(:context) do
      table :authors
      as_of_table :publishers
      as_of_table :books do |t|
        t.references :author
        t.references :publisher
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_1: {id: 100}
        },
        "Book" => {
          book_1_v1: {id: 100, author_id: 100, publisher_id: 100, period: t+2...t+3},
          book_1_v2: {id: 100, author_id: 100, publisher_id: 101, period: t+3...nil},
          book_2_v1: {id: 101, author_id: 100, publisher_id: 101, period: t+4...nil}
        },
        "Publisher" => {
          publisher_1_v1: {id: 100, period: t+1...t+4},
          publisher_2_v1: {id: 101, period: t+3...t+5},
          publisher_2_v2: {id: 101, period: t+5...nil}

        }
      }
    end

    shared_context "non-distinct timeline" do
      let(:timeline) do
        {
          nil => [[author_1, {publishers: [publisher_2_v2, publisher_2_v2]}]],
          t+1 => [[author_1, {publishers: []}]],
          t+2 => [[author_1, {publishers: [publisher_1_v1]}]],
          t+3 => [[author_1, {publishers: [publisher_2_v1]}]],
          t+4 => [[author_1, {publishers: [publisher_2_v1, publisher_2_v1]}]],
          t+5 => [[author_1, {publishers: [publisher_2_v2, publisher_2_v2]}]]
        }
      end
    end

    shared_context "distinct timeline" do
      let(:timeline) do
        {
          nil => [[author_1, {publishers: [publisher_2_v2]}]],
          t+1 => [[author_1, {publishers: []}]],
          t+2 => [[author_1, {publishers: [publisher_1_v1]}]],
          t+3 => [[author_1, {publishers: [publisher_2_v1]}]],
          t+4 => [[author_1, {publishers: [publisher_2_v1]}]],
          t+5 => [[author_1, {publishers: [publisher_2_v2]}]]
        }
      end
    end

    describe "#eager_load" do
      include_context "distinct timeline"

      test_eager_loading(n_steps: 6) { Author.eager_load(:publishers) }
    end

    describe "#preload" do
      include_context "non-distinct timeline"

      test_eager_loading(n_steps: 6) { Author.preload(:publishers) }
    end

    describe "association reader" do
      include_context "non-distinct timeline"

      test_association_reader(n_steps: 6)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
