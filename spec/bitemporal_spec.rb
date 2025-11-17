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
end

# rubocop:enable Layout/SpaceAroundOperators
