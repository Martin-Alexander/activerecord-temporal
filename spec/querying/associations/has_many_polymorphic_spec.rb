# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "has many polymorphic" do
  before do
    model "Author", as_of: true do
      has_many :pics, temporal: true, as: :picable
    end
    model "Pic", as_of: true do
      belongs_to :picable, temporal: true, polymorphic: true
    end
  end

  t = Time.parse("2000-01-01")

  context "when all tables have period columns" do
    before(:context) do
      as_of_table :authors
      as_of_table :pics do |t|
        t.bigint :picable_id
        t.string :picable_type
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_1_v1: {id: 1, period: t+1...t+3},
          author_1_v2: {id: 1, period: t+3...t+5},
          author_1_v3: {id: 1, period: t+5...nil},
          author_2_v1: {id: 2, period: t+2...t+4},
          author_2_v2: {id: 2, period: t+4...t+6},
          author_2_v3: {id: 2, period: t+6...nil}
        },
        "Pic" => {
          pic_v1: {id: 1, picable_type: "Author", picable_id: 1, period: t+2...t+4},
          pic_v2: {id: 1, picable_type: "Author", picable_id: 1, period: t+4...t+7},
          pic_v3: {id: 1, picable_type: "Author", picable_id: 2, period: t+7...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_1_v1, {pics: []}],
          [author_1_v2, {pics: []}],
          [author_1_v3, {pics: []}],
          [author_2_v1, {pics: [pic_v3]}],
          [author_2_v2, {pics: [pic_v3]}],
          [author_2_v3, {pics: [pic_v3]}]
        ],
        t+1 => [
          [author_1_v1, {pics: []}]
        ],
        t+2 => [
          [author_1_v1, {pics: [pic_v1]}],
          [author_2_v1, {pics: []}]
        ],
        t+3 => [
          [author_1_v2, {pics: [pic_v1]}],
          [author_2_v1, {pics: []}]
        ],
        t+4 => [
          [author_1_v2, {pics: [pic_v2]}],
          [author_2_v2, {pics: []}]
        ],
        t+5 => [
          [author_1_v3, {pics: [pic_v2]}],
          [author_2_v2, {pics: []}]
        ],
        t+6 => [
          [author_1_v3, {pics: [pic_v2]}],
          [author_2_v3, {pics: []}]
        ],
        t+7 => [
          [author_1_v3, {pics: []}],
          [author_2_v3, {pics: [pic_v3]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 8) { Author.eager_load(:pics) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 8) { Author.preload(:pics) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 8)
    end
  end

  context "when target table has no period column" do
    before(:context) do
      as_of_table :authors
      table :pics do |t|
        t.bigint :picable_id
        t.string :picable_type
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_1_v1: {id: 1, period: t+1...t+3},
          author_1_v2: {id: 1, period: t+3...nil}
        },
        "Pic" => {
          pic_1: {id: 1, picable_type: "Author", picable_id: 1}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_1_v1, {pics: [pic_1]}],
          [author_1_v2, {pics: [pic_1]}]
        ],
        t+1 => [
          [author_1_v1, {pics: [pic_1]}]
        ],
        t+2 => [
          [author_1_v1, {pics: [pic_1]}]
        ],
        t+3 => [
          [author_1_v2, {pics: [pic_1]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 4) { Author.eager_load(:pics) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 4) { Author.preload(:pics) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 4)
    end
  end

  context "when source table has no period column" do
    before(:context) do
      table :authors
      as_of_table :pics do |t|
        t.bigint :picable_id
        t.string :picable_type
      end
    end
    after(:context) { drop_all_tables }

    build_records do
      {
        "Author" => {
          author_bob: {id: 1},
          author_sam: {id: 2}
        },
        "Pic" => {
          pic_v1: {id: 1, picable_type: "Author", picable_id: 1, period: t+1...t+2},
          pic_v2: {id: 1, picable_type: "Author", picable_id: 1, period: t+2...t+3},
          pic_v3: {id: 1, picable_type: "Author", picable_id: 2, period: t+3...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [author_bob, {pics: []}],
          [author_sam, {pics: [pic_v3]}]
        ],
        t+1 => [
          [author_bob, {pics: [pic_v1]}],
          [author_sam, {pics: []}]
        ],
        t+2 => [
          [author_bob, {pics: [pic_v2]}],
          [author_sam, {pics: []}]
        ],
        t+3 => [
          [author_bob, {pics: []}],
          [author_sam, {pics: [pic_v3]}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 4) { Author.eager_load(:pics) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 4) { Author.preload(:pics) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 4)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
