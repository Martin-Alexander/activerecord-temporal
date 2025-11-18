require "spec_helper"

RSpec.describe SystemVersioning::SchemaStatements do
  before do
    conn.create_table :authors do |t|
      t.string :first_name
      t.string :last_name
    end

    conn.create_table :authors_history, primary_key: [:id, :sys_period] do |t|
      t.bigint :id, null: false
      t.string :first_name
      t.string :last_name
      t.tstzrange :sys_period, null: false
    end

    conn.create_table :books, primary_key: [:id, :version] do |t|
      t.bigserial :id, null: false
      t.bigint :version, null: false, default: 1
      t.string :name
      t.tstzrange :period, null: false
    end

    conn.create_table :books_history, primary_key: [:id, :version, :sys_period] do |t|
      t.bigint :id, null: false
      t.bigint :version, null: false
      t.string :name
      t.tstzrange :period, null: false
      t.tstzrange :sys_period, null: false
    end
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  describe "#create_versioning_hook" do
    it "creates hook" do
      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name]
      )

      function_names = test_conn.plpgsql_functions.map(&:name)

      insert_id = Digest::SHA256.hexdigest("authors_insert").first(10)
      update_id = Digest::SHA256.hexdigest("authors_update").first(10)
      delete_id = Digest::SHA256.hexdigest("authors_delete").first(10)

      expect(function_names).to include(
        "sys_ver_func_#{insert_id}",
        "sys_ver_func_#{update_id}",
        "sys_ver_func_#{delete_id}"
      )

      expect(test_conn.triggers(:authors)).to contain_exactly(
        "versioning_insert_trigger",
        "versioning_update_trigger",
        "versioning_delete_trigger"
      )

      expect(conn.versioning_hook(:authors)).to have_attributes(
        source_table: "authors",
        history_table: "authors_history",
        columns: %w[id first_name last_name],
        primary_key: "id"
      )
    end

    it "creates hook with custom primary key" do
      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name],
        primary_key: [:id, :first_name, :last_name]
      )

      expect(conn.versioning_hook(:authors)).to have_attributes(
        source_table: "authors",
        history_table: "authors_history",
        columns: %w[id first_name last_name],
        primary_key: %w[id first_name last_name]
      )
    end

    it "columns: all adds all columns from the source table" do
      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: :all
      )

      expect(conn.versioning_hook(:authors)).to have_attributes(
        source_table: "authors",
        history_table: "authors_history",
        columns: %w[id first_name last_name],
        primary_key: "id"
      )
    end

    it "raises an error if columns don't match" do
      conn.create_table :movies do |t|
        t.string :title
        t.bigint :director
      end

      conn.create_table :movies_history, primary_key: [:id, :sys_period] do |t|
        t.bigint :id, null: false
        t.string :director
        t.string :producer
        t.tstzrange :sys_period, null: false
      end

      expect do
        conn.create_versioning_hook(:movies, :movies_history, columns: [:id, :title])
      end.to raise_error(ArgumentError, "table 'movies_history' does not have column 'title'")

      expect do
        conn.create_versioning_hook(:movies, :movies_history, columns: [:id, :producer])
      end.to raise_error(ArgumentError, "table 'movies' does not have column 'producer'")

      expect do
        conn.create_versioning_hook(:movies, :movies_history, columns: [:id, :director])
      end.to raise_error(ArgumentError, "table 'movies_history' does not have column 'director' of type 'integer'")
    end

    it "raises an error if source table doesn't have columns in primary key" do
      expect do
        conn.create_versioning_hook(
          :authors,
          :authors_history,
          columns: [:id, :first_name, :last_name],
          primary_key: :name
        )
      end.to raise_error(ArgumentError, "table 'authors' does not have column 'name'")
    end

    it "raises an error if the hook already exists" do
      create_hook = -> do
        conn.create_versioning_hook(
          :authors,
          :authors_history,
          columns: [:first_name, :last_name]
        )
      end

      create_hook.call

      expect(&create_hook)
        .to raise_error(ActiveRecord::StatementInvalid, /PG::DuplicateFunction/)
    end

    it "handles table names with single quotes and spaces" do
      conn.rename_table(:authors, "bob's authors")

      conn.create_versioning_hook(
        "bob's authors",
        :authors_history,
        columns: [:id, :first_name, :last_name]
      )

      expect(conn.versioning_hook("bob's authors")).to have_attributes(
        source_table: "bob's authors",
        history_table: "authors_history",
        columns: %w[id first_name last_name],
        primary_key: "id"
      )
    end

    it "handles column names with single quotes and spaces" do
      conn.rename_column(:authors, :first_name, "Author's First Name")
      conn.rename_column(:authors_history, :first_name, "Author's First Name")

      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, "Author's First Name", :last_name]
      )

      expect(conn.versioning_hook(:authors)).to have_attributes(
        source_table: "authors",
        history_table: "authors_history",
        columns: ["id", "Author's First Name", "last_name"],
        primary_key: "id"
      )
    end
  end

  describe "#drop_versioning_hook" do
    before do
      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name]
      )
    end

    it "drops the hook" do
      conn.drop_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name]
      )

      expect(test_conn.plpgsql_functions.length).to eq(0)
      expect(test_conn.triggers(:authors).length).to eq(0)
    end

    it "raises an error if the hook doesn't exist" do
      drop_hook = -> do
        conn.drop_versioning_hook(
          :authors,
          :authors_history,
          columns: [:id, :first_name, :last_name]
        )
      end

      drop_hook.call

      expect(&drop_hook)
        .to raise_error(ActiveRecord::StatementInvalid, /PG::UndefinedFunction/)
    end
  end

  describe "#versioning_hook" do
    before do
      conn.create_versioning_hook(
        :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name]
      )
    end

    it "returns the hook" do
      expect(conn.versioning_hook(:authors)).to have_attributes(
        source_table: "authors",
        history_table: "authors_history",
        columns: contain_exactly("id", "first_name", "last_name"),
        primary_key: "id"
      )
    end

    it "returns nil if the hook does not exist" do
      conn.create_table :movies
      conn.create_table :movies_history

      expect(conn.versioning_hook(:movies)).to be_nil
      expect(conn.versioning_hook(:foo)).to be_nil
    end
  end

  describe "#change_versioning_hook" do
    before do
      conn.create_versioning_hook :authors,
        :authors_history,
        columns: [:id, :first_name, :last_name]

      conn.create_versioning_hook :books,
        :books_history,
        columns: [:id, :name],
        primary_key: [:id, :version]
    end

    describe "add_columns" do
      subject do
        conn.change_versioning_hook :authors,
          :authors_history,
          add_columns: [:age]
      end

      it "adds columns to hook" do
        conn.add_column(:authors, :age, :integer)
        conn.add_column(:authors_history, :age, :integer)

        subject

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns)
          .to contain_exactly("id", "first_name", "last_name", "age")
      end

      it "preserves the hooks primary key" do
        conn.add_column(:books, :pages, :integer)
        conn.add_column(:books_history, :pages, :integer)

        conn.change_versioning_hook :books,
          :books_history,
          add_columns: [:pages]

        versioning_hook = conn.versioning_hook(:books)

        expect(versioning_hook).to have_attributes(
          columns: contain_exactly("id", "name", "pages"),
          primary_key: ["id", "version"]
        )
      end

      it "raises an error if source table does not have added column" do
        conn.add_column(:authors_history, :age, :integer)

        expect { subject }
          .to raise_error(ArgumentError, "table 'authors' does not have column 'age'")

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "first_name", "last_name")
      end

      it "raises an error if history table does not have added column" do
        conn.add_column(:authors, :age, :integer)

        expect { subject }
          .to raise_error(ArgumentError, "table 'authors_history' does not have column 'age'")

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "first_name", "last_name")
      end

      it "raises an error if column types do not match" do
        conn.add_column(:authors, :age, :string)
        conn.add_column(:authors_history, :age, :integer)

        expect { subject }
          .to raise_error(ArgumentError, "table 'authors_history' does not have column 'age' of type 'string'")

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "first_name", "last_name")
      end

      it "raises an error if either table does not exist" do
        expect do
          conn.change_versioning_hook(
            :foo,
            :authors_history,
            add_columns: [:age]
          )
        end.to raise_error(ArgumentError, "table 'foo' does not exist")

        expect do
          conn.change_versioning_hook(
            :authors,
            :foo,
            add_columns: [:age]
          )
        end.to raise_error(ArgumentError, "table 'foo' does not exist")

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "first_name", "last_name")
      end
    end

    describe "remove_columns" do
      it "removes columns from hook" do
        conn.change_versioning_hook(
          :authors,
          :authors_history,
          remove_columns: [:first_name]
        )

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "last_name")
      end

      # TODO: Handle the case where the last columns are removed
      # it "removes all columns" do
      #   conn.change_versioning_hook :books,
      #     :books_history,
      #     remove_columns: [:id, :name]

      #   # ???
      # end

      it "preserves the hooks primary key" do
        conn.change_versioning_hook :books,
          :books_history,
          remove_columns: [:name]

        versioning_hook = conn.versioning_hook(:books)

        expect(versioning_hook).to have_attributes(
          columns: eq(["id"]),
          primary_key: ["id", "version"]
        )
      end

      it "raises an error if hook does not have those columns" do
        expect do
          conn.change_versioning_hook(
            :authors,
            :authors_history,
            remove_columns: [:middle_name]
          )
        end.to raise_error(ArgumentError, "versioning hook between 'authors' and 'authors_history' does not have column 'middle_name'")
      end

      it "raises an error if either table does not exist" do
        expect do
          conn.change_versioning_hook(
            :foo,
            :authors_history,
            remove_columns: [:first_name]
          )
        end.to raise_error(ArgumentError, "table 'foo' does not exist")

        expect do
          conn.change_versioning_hook(
            :authors,
            :foo,
            remove_columns: [:first_name]
          )
        end.to raise_error(ArgumentError, "table 'foo' does not exist")

        versioning_hook = conn.versioning_hook(:authors)

        expect(versioning_hook.columns).to contain_exactly("id", "first_name", "last_name")
      end
    end

    it "can add and remove columns at the same time" do
      conn.add_column(:authors, :age, :integer)
      conn.add_column(:authors_history, :age, :integer)

      conn.change_versioning_hook(
        :authors,
        :authors_history,
        add_columns: [:age],
        remove_columns: [:first_name]
      )

      versioning_hook = conn.versioning_hook(:authors)

      expect(versioning_hook.columns).to contain_exactly("id", "last_name", "age")
    end
  end

  describe "#create_table_with_system_versioning" do
    it "creates a source table and history table" do
      conn.create_table :teams

      conn.create_table_with_system_versioning :employees do |t|
        t.string :adp_id, null: false, limit: 100
        t.decimal :salary, precision: 10, scale: 2
        t.string :full_name, collation: "en_US"
        t.integer :level, comment: "this is a comment"
        t.date :started_at, default: "2025-01-01"
        t.references :team, foreign_key: true, index: true
        t.index :full_name, name: "index_employees_on_full_name"
        t.unique_constraint :adp_id, name: "unique_adp_id"
      end

      source_table = test_conn.table(:employees)
      history_table = test_conn.table(:employees_history)

      expect(source_table.primary_key).to eq("id")
      expect(source_table.indexes.length).to eq(3)
      expect(source_table.foreign_keys.length).to eq(1)
      expect(source_table).to have_column(:full_name)

      expect(history_table.primary_key).to eq(["id", "system_period"])
      expect(history_table.indexes.length).to eq(1) # the exclusion constraint
      expect(history_table.foreign_keys).to be_empty
      expect(history_table).to have_column(
        :id, :integer, sql_type: "bigint"
      )
      expect(history_table).to have_column(
        :system_period, :tstzrange, sql_type: "tstzrange", null: false
      )
      expect(history_table).to have_column(
        :adp_id, :string, sql_type: "character varying(100)", null: false
      )
      expect(history_table).to have_column(
        :salary, :decimal, sql_type: "numeric(10,2)"
      )
      expect(history_table).to have_column(
        :full_name, :string, sql_type: "character varying", collation: "en_US"
      )
      expect(history_table).to have_column(
        :level, :integer, sql_type: "integer"
      )
      expect(history_table).to have_column(
        :started_at, :date, sql_type: "date", default: nil # Don't use defaults
      )
      expect(history_table).to have_column(
        :team_id, :integer, sql_type: "bigint"
      )
      expect(history_table.exclusion_constraints.sole).to have_attributes(
        expression: "id WITH =, system_period WITH &&",
        options: hash_including(using: :gist)
      )
    end

    it "creates a history hook between the source and history table" do
      conn.create_table_with_system_versioning :employees do |t|
        t.string :full_name
      end

      versioning_hook = conn.versioning_hook(:employees)

      expect(versioning_hook).to have_attributes(
        source_table: "employees",
        history_table: "employees_history",
        columns: ["id", "full_name"],
        primary_key: "id"
      )
    end

    it "creates tables and hooks when with a non-default primary key" do
      conn.create_table_with_system_versioning :employees, primary_key: :entity_id do |t|
        t.string :full_name
      end

      source_table = test_conn.table(:employees)
      history_table = test_conn.table(:employees_history)
      versioning_hook = conn.versioning_hook(:employees)

      expect(source_table.primary_key).to eq("entity_id")
      expect(history_table.primary_key).to eq(["entity_id", "system_period"])
      expect(versioning_hook.primary_key).to eq("entity_id")
      expect(history_table.exclusion_constraints.sole).to have_attributes(
        expression: "entity_id WITH =, system_period WITH &&",
        options: hash_including(using: :gist)
      )
    end

    it "creates tables and hooks when with a composite primary key" do
      conn.create_table_with_system_versioning :employees, primary_key: [:entity_id, :version] do |t|
        t.bigserial :entity_id, null: false
        t.integer :version, null: false, default: 1
        t.string :full_name
      end

      source_table = test_conn.table(:employees)
      history_table = test_conn.table(:employees_history)
      versioning_hook = conn.versioning_hook(:employees)

      expect(source_table.primary_key)
        .to eq(["entity_id", "version"])
      expect(history_table.primary_key)
        .to eq(["entity_id", "version", "system_period"])
      expect(versioning_hook.primary_key)
        .to eq(["entity_id", "version"])

      expect(history_table).to have_column(
        :entity_id, :integer, sql_type: "bigint", null: false
      )
      expect(history_table).to have_column(
        :version, :integer, sql_type: "bigint", null: false, default: nil
      )
      expect(history_table).to have_column(
        :full_name, :string
      )
      expect(history_table).to have_column(
        :system_period, :tstzrange, sql_type: "tstzrange", null: false
      )
      expect(history_table.exclusion_constraints.sole).to have_attributes(
        expression: "entity_id WITH =, version WITH =, system_period WITH &&",
        options: hash_including(using: :gist)
      )
    end
  end

  describe "#drop_table_with_system_versioning" do
    it "drops the tables and versioning hook" do
      conn.create_table_with_system_versioning :employees do |t|
        t.string :full_name
      end

      conn.drop_table_with_system_versioning(:employees)

      expect(conn.table_exists?(:employees)).to eq(false)
      expect(conn.table_exists?(:employees_history)).to eq(false)
      expect(conn.versioning_hook(:employees)).to be_nil
    end

    it "drops tables and versioning hook with options" do
      expect do
        conn.drop_table_with_system_versioning(:employees, if_exists: true)
      end.not_to raise_error
    end

    it "drops multiple tables" do
      conn.create_table_with_system_versioning :cakes do |t|
        t.string :name
      end
      conn.create_table_with_system_versioning :pies do |t|
        t.string :name
      end

      conn.drop_table_with_system_versioning(:cakes, :pies)

      %w[cakes pies].each do |table|
        expect(conn.table_exists?(table)).to eq(false)
        expect(conn.table_exists?("#{table}_history")).to eq(false)
        expect(conn.versioning_hook(table)).to be_nil
      end
    end
  end
end
