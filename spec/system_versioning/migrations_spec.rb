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

    migration_klass.define_method(:change, &migration_change)

    migration_klass.new
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
