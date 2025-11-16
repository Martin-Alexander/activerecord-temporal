# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe Querying, "predicate builder" do
  before do
    table :authors, primary_key: [:id, :version] do |t|
      t.bigint :id
      t.bigserial :version
      t.tstzrange :period
      t.string :name
    end

    model "Author", as_of: true
  end

  after { drop_all_tables }

  t = Time.utc(2000)

  build_records do
    {
      "Author" => {
        author_bob_v1: {id: 1, name: "Bob", period: t+1...t+3},
        author_bob_v2: {id: 1, name: "Bob", period: t+3...t+5},
        author_bob_v3: {id: 1, name: "Bob", period: t+5...nil},
        author_sam_v1: {id: 2, name: "Sam", period: t+2...t+4},
        author_sam_v2: {id: 2, name: "Sam", period: t+4...t+6},
        author_sam_v3: {id: 2, name: "Sam", period: t+6...nil}
      }
    }
  end

  describe "::contains" do
    it "scopes records to a time" do
      expect(Author.where(period: Author.contains(t+3)))
        .to contain_exactly(author_bob_v2, author_sam_v1)
      expect(Author.where(period: Author.contains(t+5)))
        .to contain_exactly(author_bob_v3, author_sam_v2)
      expect(Author.where(period: Author.contains(t+99)))
        .to contain_exactly(author_bob_v3, author_sam_v3)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
