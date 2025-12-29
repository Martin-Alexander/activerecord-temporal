# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "bitemporal" do
  before do
    system_versioned_table :authors, primary_key: [:id, :version] do |t|
      t.bigserial :id, null: false
      t.bigint :version, null: false, default: 1
      t.string :name
      t.tstzrange :validity, null: false
    end

    system_versioned_table :books, primary_key: [:id, :version] do |t|
      t.bigserial :id, null: false
      t.bigint :version, null: false, default: 1
      t.bigint :author_id
      t.string :name
      t.tstzrange :validity, null: false
    end

    history_model_namespace

    model "ApplicationRecord" do
      self.abstract_class = true

      include ActiveRecord::Temporal

      system_versioning
      application_versioning dimensions: :validity
    end

    model "Author", ApplicationRecord do
      application_versioned
      system_versioned

      has_many :books, temporal: true
    end

    model "Book", ApplicationRecord do
      application_versioned
      system_versioned

      belongs_to :author, temporal: true
    end
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  t = Time.utc(2000)

  it "version models have both time dimensions" do
    expect(History::Author.time_dimensions)
      .to contain_exactly(:system_period, :validity)
  end

  it "as of queries work across both time dimensions" do
    trx_1 = transaction_time { Author.create!(validity: t...) }
    trx_2 = transaction_time { Author.sole.update!(validity: t+1...) }

    expect(History::Author.as_of(validity: t, system_period: trx_2))
      .to be_empty

    expect(History::Author.as_of(validity: t, system_period: trx_1))
      .to_not be_empty
  end

  it "associations" do
    t = Time.utc(2000)

    author = Author.originate_at(t+1).with(name: "Bob")
    Book.originate_at(t+1).with(name: "foo", author: author)
    Book.originate_at(t+1).with(name: "bar", author: author)

    author.books.find_by(name: "foo").revise_at(t+2).with(name: "foobar")
    author.books.find_by(name: "bar").inactivate_at(t+2)

    expect(author.as_of(t+1).books.count).to eq(2)
    expect(author.as_of(t+2).books.count).to eq(1)
  end
end

# rubocop:enable Layout/SpaceAroundOperators
