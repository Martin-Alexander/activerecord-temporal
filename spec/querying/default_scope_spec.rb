# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe Querying, "default scope" do
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

    model "Author", as_of: true do
      has_many :books, temporal: true
    end
    model "Book", as_of: true
  end

  after { drop_all_tables }

  t = Time.utc(2000)

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
      }
    }
  end

  it "adds default scope to models" do
    authors = Querying::Scoping.at({period: t+2}) do
      Author.all
    end

    expect(authors).to contain_exactly(author_bob_v1, author_sam_v1)

    authors = Querying::Scoping.at(t+2) do
      Author.all
    end

    expect(authors).to contain_exactly(author_bob_v1, author_sam_v1)

    expect(Author.all.size).to eq(6)
  end

  it "is over written by as_of" do
    Querying::Scoping.at({period: t+2}) do
      expect(Author.all).to contain_exactly(author_bob_v1, author_sam_v1)
      expect(Author.as_of(t+3)).to contain_exactly(author_bob_v2, author_sam_v1)
    end
  end

  it "is over written by at_time" do
    Querying::Scoping.at({period: t+2}) do
      expect(Author.at_time(t+3)).to contain_exactly(author_bob_v2, author_sam_v1)
    end
  end

  it "does not set time scope on relation or records" do
    Querying::Scoping.at({period: t+2}) do
      authors = Author.all

      expect(authors.time_tag_values).to eq({})
      expect(authors.first.time_tag).to be_nil
    end
  end

  it "does not interfere with setting time scops" do
    Querying::Scoping.at({period: t+2}) do
      authors = Author.as_of(t+3)

      expect(authors.time_tag_values).to eq({period: t+3})
      expect(authors.first.time_tag).to eq(t+3)
    end
  end

  it "applies a scope the persists outside the block" do
    authors = nil

    Querying::Scoping.at({period: t+2}) do
      authors = Author.all
    end

    expect(authors).to contain_exactly(author_bob_v1, author_sam_v1)
  end

  it "does not overwrite time scopes from outside the block" do
    authors = Author.as_of(t+3)

    Querying::Scoping.at({period: t+2}) do
      expect(authors).to contain_exactly(author_bob_v2, author_sam_v1)
      expect(authors.time_tag_values).to eq({period: t+3})
      expect(authors.first.time_tag).to eq(t+3)
    end
  end

  it "applies its scope to associations" do
    Querying::Scoping.at({period: t+2}) do
      expect(Author.first.books).to contain_exactly(foo_v1)
    end
  end

  it "is nestable" do
    expect(Author.count).to eq(6)

    Querying::Scoping.at({period: t+2}) do
      expect(Author.all).to contain_exactly(author_bob_v1, author_sam_v1)

      Querying::Scoping.at({period: t+3}) do
        expect(Author.all).to contain_exactly(author_bob_v2, author_sam_v1)
      end

      expect(Author.all).to contain_exactly(author_bob_v1, author_sam_v1)
    end

    expect(Author.count).to eq(6)
  end

  it "each level mergers with outer level" do
    conn.add_column(:authors, :system_period, :tstzrange, null: false, default: t...)

    Author.time_dimensions = :period, :system_period
    Author.reset_column_information

    author_bob_v1.reload.update!(system_period: t+3...)

    Querying::Scoping.at({period: t+2}) do
      expect(Author.all).to contain_exactly(author_bob_v1, author_sam_v1)

      Querying::Scoping.at({system_period: t+2}) do
        expect(Author.all).to contain_exactly(author_sam_v1)
      end

      expect(Author.all).to contain_exactly(author_bob_v1, author_sam_v1)
    end

    expect(Author.count).to eq(6)
  end
end

# rubocop:enable Layout/SpaceAroundOperators
