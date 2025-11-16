# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe Querying do
  before do
    table :authors, primary_key: [:id, :version] do |t|
      t.bigint :id
      t.bigserial :version
      t.tstzrange :period
      t.string :name
    end
    table :libraries do |t|
      t.string :name
    end

    model "Author", as_of: true
    model "Book", as_of: true
    model "Library", as_of: true
  end

  after { drop_all_tables }

  t = Time.parse("2000-01-01")

  build_records do
    {
      "Author" => {
        author_bob_v1: {id: 1, name: "Bob", period: t+1...t+3},
        author_bob_v2: {id: 1, name: "Bob", period: t+3...t+5},
        author_bob_v3: {id: 1, name: "Bob", period: t+5...nil},
        author_sam_v1: {id: 2, name: "Sam", period: t+2...t+4},
        author_sam_v2: {id: 2, name: "Sam", period: t+4...t+6},
        author_sam_v3: {id: 2, name: "Sam", period: t+6...nil}
      },
      "Library" => {
        library_foo: {name: "Foo"},
        library_bar: {name: "Bar"}
      }
    }
  end

  it "does not temporally scope by default" do
    expect(Author.all.size).to eq(6)
    expect(Author.count).to eq(6)
  end

  describe "::at_time" do
    it "scopes to records existing as of given time" do
      expect(Author.at_time(t+3))
        .to contain_exactly(author_bob_v2, author_sam_v1)
      expect(Author.at_time(t+5))
        .to contain_exactly(author_bob_v3, author_sam_v2)
      expect(Author.at_time(t+99))
        .to contain_exactly(author_bob_v3, author_sam_v3)
    end

    context "when column does not exist" do
      it "does not scope" do
        expect(Library.at_time(t+3)).to eq(Library.all)
        expect(Library.at_time(t+99)).to eq(Library.all)
      end
    end
  end

  describe "::as_of" do
    it "scopes by as-of and tags loaded records" do
      time = t+3
      relation = Author.as_of(time)

      expect(relation)
        .to contain_exactly(author_bob_v2, author_sam_v1)
      expect(relation)
        .to all(have_attributes(time_tag: t+3))
    end

    context "when column does not exist" do
      it "does not scope but still tags loaded records" do
        time = t+3
        relation = Library.as_of(time)

        expect(Library.as_of(time)).to eq(Library.all)
        expect(relation).to all(have_attributes(time_tag: time))
      end
    end
  end

  describe "#as_of!" do
    it "tags the record" do
      author_bob_v1.as_of!(t+2)
      author_sam_v3.as_of!(t+9)
      library_foo.as_of!(t-99)
      library_bar.as_of!(t+99)

      expect(author_bob_v1.time_tag).to eq(t+2)
      expect(author_sam_v3.time_tag).to eq(t+9)
      expect(library_foo.time_tag).to eq(t-99)
      expect(library_bar.time_tag).to eq(t+99)
    end

    it "reloads the record" do
      author_sam_v3.name = "zoop"

      author_sam_v3.as_of!(t+9)

      expect(author_sam_v3.name).to_not eq("zoop")
    end

    it "raises an error if the time is outside the record's as-of range" do
      expect { author_bob_v1.as_of!(t+3) }.to raise_error(
        Querying::RangeError,
        "#{t+3} is outside of 'period' range"
      )

      expect { author_sam_v3.as_of!(t+5) }.to raise_error(
        Querying::RangeError,
        "#{t+5} is outside of 'period' range"
      )
    end
  end

  describe "#as_of" do
    it "returns a new tagged record" do
      author_bob_v1_tagged = author_bob_v1.as_of(t+2)
      author_sam_v3_tagged = author_sam_v3.as_of(t+9)
      library_foo_tagged = library_foo.as_of(t-99)
      library_bar_tagged = library_bar.as_of(t+99)

      expect(author_bob_v1_tagged.time_tag).to eq(t+2)
      expect(author_sam_v3_tagged.time_tag).to eq(t+9)
      expect(library_foo_tagged.time_tag).to eq(t-99)
      expect(library_bar_tagged.time_tag).to eq(t+99)
    end

    it "returns nil if the time is outside the record's as-of range" do
      author_bob_v1_tagged = author_bob_v1.as_of(t+3)
      author_sam_v3_tagged = author_sam_v3.as_of(t+5)

      expect(author_bob_v1_tagged).to be_nil
      expect(author_sam_v3_tagged).to be_nil
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
