require "spec_helper"

RSpec.describe ActiveRecord::Temporal::ApplicationVersioning::SchemaStatements do
  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  describe "#create_application_versioned_table" do
    it "creates primary key, columns, and constraints" do
      conn.create_application_versioned_table :authors do |t|
        t.string :name
      end

      authors = test_conn.table(:authors)

      expect(authors.primary_key).to eq(["id", "version"])
      expect(authors).to have_column(:name, :string)
      expect(authors).to have_column(:validity, :tstzrange, null: false)
      expect(authors).to have_column(:id, :integer, default_function: "nextval('authors_id_seq'::regclass)", null: false, sql_type: "bigint")
      expect(authors).to have_column(:version, :integer, null: false, default: "1", sql_type: "bigint")
      expect(authors.exclusion_constraints.sole).to have_attributes(
        expression: "id WITH =, validity WITH &&",
        options: hash_including(using: :gist)
      )
    end

    it "adds 'version' given primary key" do
      conn.create_application_versioned_table :authors, primary_key: :entity_id do |t|
        t.string :name
      end

      authors = test_conn.table(:authors)

      expect(authors.primary_key).to eq(["entity_id", "version"])
      expect(authors).to have_column(:name, :string)
      expect(authors).to have_column :entity_id,
        :integer,
        default_function: "nextval('authors_id_seq'::regclass)",
        null: false,
        sql_type: "bigint"
      expect(authors.exclusion_constraints.sole).to have_attributes(
        expression: "entity_id WITH =, validity WITH &&",
        options: hash_including(using: :gist)
      )
    end

    it "adds 'version' given composite primary key" do
      conn.create_application_versioned_table :authors, primary_key: [:id, :entity_id] do |t|
        t.bigserial :entity_id, null: false
        t.bigint :id, null: false
        t.string :name
      end

      authors = test_conn.table(:authors)

      expect(authors.primary_key).to contain_exactly(*%w[id entity_id version])
      expect(authors).to have_column(:name, :string)
      expect(authors).to have_column(:id, :integer, null: false, sql_type: "bigint")
      expect(authors).to have_column :entity_id,
        :integer,
        default_function: "nextval('authors_id_seq'::regclass)",
        null: false,
        sql_type: "bigint"
      expect(authors.exclusion_constraints.sole).to have_attributes(
        expression: "id WITH =, entity_id WITH =, validity WITH &&",
        options: hash_including(using: :gist)
      )
    end
  end
end
