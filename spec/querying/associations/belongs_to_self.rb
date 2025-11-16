# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "belongs to self" do
  before do
    model "User", as_of: true do
      belongs_to :fav, temporal: true, class_name: "User"
    end
  end

  t = Time.parse("2000-01-01")

  context "when the table has a period column" do
    before(:context) do
      as_of_table :users
      conn.add_reference(:users, :fav)
    end
    after(:context) { drop_all_tables }

    #     |      user_1      |      user_2
    # ------------------------------------------
    # t+1 |                  |
    # t+2 | v1  fav:         |
    # t+3 | v1  fav:         | v1  fav:
    # t+4 | v2  fav: user_2  | v1  fav:
    # t+5 | v2  fav: user_2  | v2  fav:
    # t+6 | v3  fav:         | v2  fav:
    # t+7 | v3  fav:         | v3  fav: user_1

    build_records do
      {
        "User" => {
          user_1_v1: {id: 100, fav_id: nil, period: t+2...t+4},
          user_1_v2: {id: 100, fav_id: 200, period: t+4...t+6},
          user_1_v3: {id: 100, fav_id: nil, period: t+6...nil},
          user_2_v1: {id: 200, fav_id: nil, period: t+3...t+5},
          user_2_v2: {id: 200, fav_id: nil, period: t+5...t+7},
          user_2_v3: {id: 200, fav_id: 100, period: t+7...nil}
        }
      }
    end

    let(:timeline) do
      {
        nil => [
          [user_1_v1, {fav: nil}],
          [user_1_v2, {fav: user_2_v3}],
          [user_1_v3, {fav: nil}],
          [user_2_v1, {fav: nil}],
          [user_2_v2, {fav: nil}],
          [user_2_v3, {fav: user_1_v3}]
        ],
        t+1 => [],
        t+2 => [[user_1_v1, {fav: nil}]],
        t+3 => [
          [user_1_v1, {fav: nil}],
          [user_2_v1, {fav: nil}]
        ],
        t+4 => [
          [user_1_v2, {fav: user_2_v1}],
          [user_2_v1, {fav: nil}]
        ],
        t+5 => [
          [user_1_v2, {fav: user_2_v2}],
          [user_2_v2, {fav: nil}]
        ],
        t+6 => [
          [user_1_v3, {fav: nil}],
          [user_2_v2, {fav: nil}]
        ],
        t+7 => [
          [user_1_v3, {fav: nil}],
          [user_2_v3, {fav: user_1_v3}]
        ]
      }
    end

    describe "#eager_load" do
      test_eager_loading(n_steps: 8) { User.eager_load(:fav) }
    end

    describe "#preload" do
      test_eager_loading(n_steps: 8) { User.preload(:fav) }
    end

    describe "association reader" do
      test_association_reader(n_steps: 8)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
