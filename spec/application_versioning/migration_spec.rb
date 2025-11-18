require "spec_helper"

RSpec.describe ActiveRecord::Temporal::ApplicationVersioning::Migration do
  migration_version = "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"

  around do |example|
    original, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false

    example.run

    ActiveRecord::Migration.verbose = original
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  let(:migration) do
    migration_klass = Class.new(ActiveRecord::Migration[migration_version])
    migration_klass.include ActiveRecord::Temporal::ApplicationVersioning::Migration

    migration_klass.define_method(:change, &migration_change)

    migration_klass.new
  end

  describe "#create_application_versioned_table" do
    let(:migration_change) do
      -> do
        create_application_versioned_table :authors do |t|
          t.string :full_name
        end
      end
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.column_exists?(:authors, :version)).to eq(true)

      migration.migrate(:down)

      expect(conn.table_exists?(:authors)).to eq(false)
    end
  end

  describe "#create_table", "application_versioning: true" do
    let(:migration_change) do
      -> do
        create_table :authors, application_versioning: true do |t|
          t.string :full_name
        end
      end
    end

    it "calls create_application_versioned_table" do
      migration.migrate(:up)

      expect(conn.column_exists?(:authors, :version)).to eq(true)
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.column_exists?(:authors, :version)).to eq(true)

      migration.migrate(:down)

      expect(conn.table_exists?(:authors)).to eq(false)
    end
  end

  describe "#create_table", "application_versioning: false" do
    let(:migration_change) do
      -> do
        create_table :authors, application_versioning: false do |t|
          t.string :full_name
        end
      end
    end

    it "doesn't call create_application_versioned_table" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.column_exists?(:authors, :version)).to eq(false)
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.column_exists?(:authors, :version)).to eq(false)

      migration.migrate(:down)

      expect(conn.table_exists?(:authors)).to eq(false)
    end
  end
end
