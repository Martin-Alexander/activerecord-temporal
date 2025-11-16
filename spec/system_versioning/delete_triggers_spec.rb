require "spec_helper"

RSpec.describe "delete triggers" do
  before do
    system_versioned_table :books do |t|
      t.string :title
      t.integer :pages
    end

    history_model_namespace

    history_model_base_class "ApplicationRecord"

    system_versioned_model "Book", ApplicationRecord
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
    conn.drop_schema("myschema", if_exists: true)
  end

  shared_examples "delete triggers" do
    it "sets current history record's upper bound system_period to the current time" do
      insert_time = transaction_time do
        Book.create!(title: "The Great Gatsby", pages: 180)
      end

      delete_time = transaction_time do
        Book.first.destroy!
      end

      expect(History::Book.count).to eq(1)
      expect(History::Book.first).to have_attributes(
        title: "The Great Gatsby",
        pages: 180,
        system_period: insert_time...delete_time
      )
    end

    context "when inserting and deleting in a single transaction" do
      it "does not create a history record" do
        conn.transaction do
          Book.create!(title: "The Great Gatsby", pages: 180)
          Book.first.destroy!
        end

        expect(History::Book.count).to eq(0)
      end
    end
  end

  include_examples "delete triggers"

  context "when the table name is schema qualified" do
    before do
      conn.create_schema("myschema")

      system_versioned_table "myschema.books" do |t|
        t.string :title
        t.integer :pages
      end

      system_versioned_model "Book", ApplicationRecord do
        self.table_name = "myschema.books"
      end
    end

    include_examples "delete triggers"
  end

  context "when column and table name has spaces and single quotes" do
    before do
      system_versioned_table "bob's books" do |t|
        t.string "book's title"
        t.integer :pages
      end

      system_versioned_model "Book", ApplicationRecord do
        self.table_name = "bob's books"
        alias_attribute :title, "book's title"
      end
    end

    include_examples "delete triggers"
  end
end
