require "spec_helper"

RSpec.describe "update triggers" do
  before do
    system_versioned_table :books do |t|
      t.string :title
      t.integer :pages
    end

    history_model_namespace

    system_versioning_base "ApplicationRecord"

    system_versioned_model "Book", ApplicationRecord
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
    conn.drop_schema("myschema", if_exists: true)
  end

  shared_examples "update triggers" do
    it "sets current history record's upper bound system_period to the current time and creates a new history record" do
      insert_time = transaction_time do
        Book.create!(title: "The Great Gatsby", pages: 180)
      end

      update_time = transaction_time do
        Book.first.update!(title: "The Greatest Gatsby")
      end

      expect(History::Book.count).to eq(2)
      expect(History::Book.find_by(title: "The Great Gatsby"))
        .to have_attributes(pages: 180, system_period: insert_time...update_time)
      expect(History::Book.find_by(title: "The Greatest Gatsby"))
        .to have_attributes(pages: 180, system_period: update_time...)
    end

    context "when the update doesn't change the record" do
      it "does not change the history table" do
        insert_time = transaction_time do
          Book.create!(title: "The Great Gatsby", pages: 180)
        end

        Book.first.update!(title: "The Great Gatsby")

        expect(History::Book.count).to eq(1)
        expect(History::Book.first).to have_attributes(
          title: "The Great Gatsby",
          pages: 180,
          system_period: insert_time...
        )
      end
    end

    context "when two updates are made in a single transaction" do
      it "merges them into a single history record" do
        insert_time = transaction_time do
          Book.create!(title: "The Great Gatsby", pages: 180)
        end

        update_time = transaction_time do
          Book.first.update!(title: "The Greatest Gatsby")
          Book.first.update!(title: "The Worst Gatsby")
          Book.first.update!(title: "The Absolutely Greatest Gatsby")
        end

        expect(History::Book.count).to eq(2)
        expect(History::Book.find_by(title: "The Great Gatsby"))
          .to have_attributes(
            title: "The Great Gatsby",
            pages: 180,
            system_period: insert_time...update_time
          )
        expect(History::Book.find_by(title: "The Absolutely Greatest Gatsby"))
          .to have_attributes(
            title: "The Absolutely Greatest Gatsby",
            pages: 180,
            system_period: update_time...
          )
      end
    end
  end

  include_examples "update triggers"

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

    include_examples "update triggers"
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

    include_examples "update triggers"
  end
end
