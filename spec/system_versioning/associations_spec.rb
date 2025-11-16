require "spec_helper"

RSpec.describe "system versioning associations" do
  before do
    table :libraries
    system_versioned_table :authors do |t|
      t.string :name
    end
    system_versioned_table :books do |t|
      t.references :author, foreign_key: true
      t.references :library, foreign_key: true
    end
    system_versioned_table :pics do |t|
      t.bigint :picable_id
      t.string :picable_type
    end

    history_model_namespace

    history_model_base_class "ApplicationRecord"

    model "Library", ApplicationRecord do
      has_many :books
      has_many :pics, as: :picable
    end
    system_versioned_model "Author", ApplicationRecord do
      has_many :books
      has_many :libraries, through: :books
      has_many :pics, as: :picable
    end
    system_versioned_model "Book", ApplicationRecord do
      belongs_to :author
      belongs_to :library
    end
    system_versioned_model "Pic", ApplicationRecord do
      belongs_to :picable, polymorphic: true
    end
  end

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  shared_examples "has many" do |model_name, history_model_name, target_history_model_name, association, as = nil|
    poly = as ? ", as: :#{as}" : ""

    it "History::#{model_name} has_many :#{association}#{poly}" do
      invers_assoc = as || model_name.underscore
      base_source = model_name.constantize
      base_target = association.to_s.singularize.camelize.constantize
      history_source = history_model_name.constantize
      history_target = target_history_model_name.constantize

      source_1 = base_source.create!
      source_2 = base_source.create!
      base_target.create(id_value: 1)
      base_target.create(:id_value => 2, invers_assoc => source_1)
      base_target.create(:id_value => 3, invers_assoc => source_1)
      base_target.create(:id_value => 4, invers_assoc => source_2)

      expect(history_source.first.send(association)).to contain_exactly(
        be_instance_of(history_target).and(have_attributes(id_value: 2)),
        be_instance_of(history_target).and(have_attributes(id_value: 3))
      )
    end
  end

  include_examples "has many", "Author", "History::Author", "History::Book", :books
  include_examples "has many", "Library", "History::Library", "History::Book", :books
  include_examples "has many", "Author", "History::Author", "History::Pic", :pics, :picable
  include_examples "has many", "Library", "History::Library", "History::Pic", :pics, :picable

  it "History::Author has_many :libraries, through: :books" do
    author_1 = Author.create!
    author_2 = Author.create!
    library_1 = Library.create!(id_value: 1)
    library_2 = Library.create!(id_value: 2)
    library_3 = Library.create!(id_value: 3)
    Book.create
    Book.create(library: library_1)
    Book.create(author: author_2, library: library_3)
    Book.create(author: author_1)
    Book.create(author: author_1, library: library_1)
    Book.create(author: author_1, library: library_2)

    expect(History::Author.first.libraries).to contain_exactly(
      be_instance_of(History::Library).and(have_attributes(id_value: 1)),
      be_instance_of(History::Library).and(have_attributes(id_value: 2))
    )
  end

  context "when not using the history model namespace" do
    before do
      model "HistoryLibrary", Library do
        include HistoryModel

        has_many :books, class_name: "HistoryBook", foreign_key: :library_id
        has_many :pics, as: :picable, class_name: "HistoryPic"
      end
      model "HistoryAuthor", Author do
        include HistoryModel

        has_many :books, class_name: "HistoryBook", foreign_key: :author_id
        has_many :libraries, through: :books, class_name: "HistoryLibrary"
        has_many :pics, as: :picable, class_name: "HistoryPic"
      end
      model "HistoryBook", Book do
        include HistoryModel

        belongs_to :author, class_name: "HistoryAuthor", foreign_key: :author_id
        belongs_to :library, class_name: "HistoryLibrary", foreign_key: :library_id
      end
      model "HistoryPic", Pic do
        include HistoryModel
      end
    end

    include_examples "has many", "Author", "HistoryAuthor", "HistoryBook", :books
    include_examples "has many", "Library", "HistoryLibrary", "HistoryBook", :books
    include_examples "has many", "Author", "HistoryAuthor", "HistoryPic", :pics, :picable
    include_examples "has many", "Library", "HistoryLibrary", "HistoryPic", :pics, :picable

    it "HistoryAuthor has_many :libraries, through: :books" do
      author_1 = Author.create!
      author_2 = Author.create!
      library_1 = Library.create!(id_value: 1)
      library_2 = Library.create!(id_value: 2)
      library_3 = Library.create!(id_value: 3)
      Book.create
      Book.create(library: library_1)
      Book.create(author: author_2, library: library_3)
      Book.create(author: author_1)
      Book.create(author: author_1, library: library_1)
      Book.create(author: author_1, library: library_2)

      expect(HistoryAuthor.first.libraries).to contain_exactly(
        be_instance_of(HistoryLibrary).and(have_attributes(id_value: 1)),
        be_instance_of(HistoryLibrary).and(have_attributes(id_value: 2))
      )
    end
  end
end
