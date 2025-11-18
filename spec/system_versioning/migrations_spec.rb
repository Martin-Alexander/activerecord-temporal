require "spec_helper"

RSpec.describe "migrations" do
  migration_version = "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"

  around do |example|
    original, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false

    example.run

    ActiveRecord::Migration.verbose = original
  end

  before do
    conn.create_table :books do |t|
      t.string :title
      t.string :author_name
      t.integer :pages
    end

    conn.create_table :books_history, primary_key: [:id, :sys_period] do |t|
      t.bigserial :id, null: false
      t.string :title
      t.string :author_name
      t.integer :pages
      t.tstzrange :sys_period, null: false
    end
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  let(:migration) do
    migration_klass = Class.new(ActiveRecord::Migration[migration_version])
    migration_klass.include ActiveRecord::Temporal::SystemVersioning::Migration

    migration_klass.define_method(:change, &migration_change)

    migration_klass.new
  end

  describe "#create_table_with_system_versioning" do
    let(:migration_change) do
      -> do
        create_table_with_system_versioning :authors do |t|
          t.string :full_name
          t.references :book, foreign_key: true
        end
      end
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.table_exists?(:authors_history)).to eq(true)
      expect(:authors)
        .to have_versioning_hook(:authors_history, [:id, :full_name, :book_id])

      migration.migrate(:down)

      expect(conn.table_exists?(:authors)).to eq(false)
      expect(conn.table_exists?(:authors_history)).to eq(false)
      expect(conn.versioning_hook(:authors)).to be_nil
    end

    context "with options" do
      let(:migration_change) do
        -> do
          create_table_with_system_versioning :authors, primary_key: :entity_id do |t|
            t.string :full_name
            t.references :book, foreign_key: true
          end
        end
      end

      it "is reversible with options" do
        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(true)
        expect(conn.table_exists?(:authors_history)).to eq(true)
        expect(:authors)
          .to have_versioning_hook(:authors_history, [:entity_id, :full_name, :book_id])

        migration.migrate(:down)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil
      end
    end
  end

  describe "#drop_table_with_system_versioning" do
    let(:migration_change) do
      -> { drop_table_with_system_versioning :authors }
    end

    it "is not reversible" do
      conn.create_table_with_system_versioning :authors

      migration.migrate(:up)

      expect { migration.migrate(:down) }
        .to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end

  describe "#create_table" do
    let(:migration_change) do
      -> do
        create_table :authors do |t|
          t.string :full_name
          t.references :book, foreign_key: true
        end
      end
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.table_exists?(:authors)).to eq(true)
      expect(conn.table_exists?(:authors_history)).to eq(false)
      expect(conn.versioning_hook(:authors)).to be_nil

      migration.migrate(:down)

      expect(conn.table_exists?(:authors)).to eq(false)
      expect(conn.table_exists?(:authors_history)).to eq(false)
      expect(conn.versioning_hook(:authors)).to be_nil
    end

    context "with system_versioning: true" do
      let(:migration_change) do
        -> do
          create_table :authors, system_versioning: true do |t|
            t.string :full_name
            t.references :book, foreign_key: true
          end
        end
      end

      it "calls #create_table_with_system_versioning" do
        migration.migrate(:up)

        source_table = test_conn.table(:authors)
        history_table = test_conn.table(:authors_history)
        versioning_hook = conn.versioning_hook(:authors)

        expect(source_table.primary_key).to eq("id")
        expect(source_table).to have_column(:full_name)

        expect(history_table.primary_key).to eq(["id", "system_period"])
        expect(source_table).to have_column(:full_name)

        expect(versioning_hook).to have_attributes(
          source_table: "authors",
          history_table: "authors_history",
          columns: ["id", "full_name", "book_id"],
          primary_key: "id"
        )
      end

      it "is reversible" do
        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(true)
        expect(conn.table_exists?(:authors_history)).to eq(true)
        expect(:authors)
          .to have_versioning_hook(:authors_history, [:id, :full_name, :book_id])

        migration.migrate(:down)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil
      end
    end

    context "with system_versioning: false" do
      let(:migration_change) do
        -> do
          create_table :authors, system_versioning: false do |t|
            t.string :full_name
            t.references :book, foreign_key: true
          end
        end
      end

      it "falls back on super" do
        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(true)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil
      end

      it "is reversible" do
        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(true)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil

        migration.migrate(:down)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil
      end
    end
  end

  describe "#drop_table" do
    context "without system versioning and without block" do
      let(:migration_change) do
        -> { drop_table :authors }
      end

      it "falls back on super when" do
        conn.create_table_with_system_versioning :authors

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(true)
        expect(conn.versioning_hook(:authors)).to be_present
      end

      it "is not reversible" do
        conn.create_table :authors

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)

        expect { migration.migrate(:down) }
          .to raise_error(ActiveRecord::IrreversibleMigration)
      end
    end

    # Reversing drop_table with block was fixed here
    # https://github.com/rails/rails/commit/94108c92bfe76fa3ed4bda03cb8dcddaf18b8aac
    if ActiveRecord.version > Gem::Version.new("8.0.1")
      context "without system versioning and with block" do
        let(:migration_change) do
          -> do
            drop_table :authors do |t|
              t.string :name
            end
          end
        end

        it "is reversible" do
          conn.create_table :authors do |t|
            t.string :name
          end

          migration.migrate(:up)

          expect(conn.table_exists?(:authors)).to eq(false)

          migration.migrate(:down)

          expect(test_conn.table(:authors)).to have_column(:name)
        end
      end
    end

    context "with system versioning and without block" do
      let(:migration_change) do
        -> { drop_table :authors, system_versioning: true }
      end

      it "calls #create_table_with_system_versioning" do
        conn.create_table_with_system_versioning :authors

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil
      end

      it "is not reversible" do
        conn.create_table_with_system_versioning :authors

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil

        expect { migration.migrate(:down) }
          .to raise_error(ActiveRecord::IrreversibleMigration)
      end
    end

    context "with system versioning and with block" do
      let(:migration_change) do
        -> do
          drop_table :authors, system_versioning: true do |t|
            t.string :name
          end
        end
      end

      it "is not reversible" do
        conn.create_table_with_system_versioning :authors do |t|
          t.string :name
        end

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil

        expect { migration.migrate(:down) }
          .to raise_error(ActiveRecord::IrreversibleMigration)
      end

      it "is reversible" do
        skip "TODO: support reversing drop_table with system versioning"

        conn.create_table_with_system_versioning :authors do |t|
          t.string :name
        end

        migration.migrate(:up)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(false)
        expect(conn.versioning_hook(:authors)).to be_nil

        migration.migrate(:down)

        expect(conn.table_exists?(:authors)).to eq(false)
        expect(conn.table_exists?(:authors_history)).to eq(true)
        expect(conn.versioning_hook(:authors)).to be_present
      end
    end
  end

  describe "#create_versioning_hook" do
    let(:migration_change) do
      -> do
        create_versioning_hook(
          :books,
          :books_history,
          columns: [:title, :author_name]
        )
      end
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(:books)
        .to have_versioning_hook(:books_history, [:title, :author_name])

      migration.migrate(:down)

      expect(conn.versioning_hook(:books)).to be_nil
    end
  end

  describe "#drop_versioning_hook" do
    before do
      conn.create_versioning_hook(
        :books,
        :books_history,
        columns: [:title, :author_name]
      )
    end

    let(:migration_change) do
      -> do
        drop_versioning_hook(
          :books,
          :books_history,
          columns: [:title, :author_name]
        )
      end
    end

    it "is reversible" do
      migration.migrate(:up)

      expect(conn.versioning_hook(:books)).to be_nil

      migration.migrate(:down)

      expect(:books)
        .to have_versioning_hook(:books_history, [:title, :author_name])
    end

    context "when columns are not provided" do
      let(:migration_change) do
        -> { drop_versioning_hook(:books, :books_history) }
      end

      it "is not reversible" do
        migration.migrate(:up)

        expect(conn.versioning_hook(:books)).to be_nil

        expect { migration.migrate(:down) }
          .to raise_error(ActiveRecord::IrreversibleMigration)
      end
    end
  end

  describe "#change_versioning_hook", "adding columns" do
    before do
      conn.create_versioning_hook(
        :books,
        :books_history,
        columns: [:title, :author_name]
      )
    end

    describe "adding columns" do
      let(:migration_change) do
        -> { change_versioning_hook(:books, :books_history, add_columns: [:pages]) }
      end

      it "is reversible" do
        migration.migrate(:up)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("title", "author_name", "pages")

        migration.migrate(:down)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("title", "author_name")
      end
    end

    describe "removing columns" do
      let(:migration_change) do
        -> { change_versioning_hook(:books, :books_history, remove_columns: [:title]) }
      end

      it "is reversible" do
        migration.migrate(:up)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("author_name")

        migration.migrate(:down)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("title", "author_name")
      end
    end

    describe "adding and removing columns" do
      let(:migration_change) do
        -> do
          change_versioning_hook(
            :books,
            :books_history,
            add_columns: [:pages],
            remove_columns: [:title]
          )
        end
      end

      it "is reversible" do
        migration.migrate(:up)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("author_name", "pages")

        migration.migrate(:down)

        expect(conn.versioning_hook(:books).columns)
          .to contain_exactly("title", "author_name")
      end
    end
  end
end
