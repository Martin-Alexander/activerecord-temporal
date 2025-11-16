# rubocop:disable Layout/SpaceAroundOperators

require "spec_helper"

RSpec.describe "multiple columns spec" do
  before do
    table :employees, primary_key: [:id, :rev, :sys_period] do |t|
      t.bigint :id
      t.bigint :rev
      t.tstzrange :validity
      t.tstzrange :sys_period
      t.integer :salary
      t.references :org
    end
    table :orgs, primary_key: [:id, :rev, :sys_period] do |t|
      t.bigint :id
      t.bigserial :rev
      t.tstzrange :validity
      t.tstzrange :sys_period
    end

    model "Employee" do
      include Querying

      self.time_dimensions = :validity, :sys_period

      belongs_to :org, temporal: true
    end

    model "Org" do
      include Querying

      self.time_dimensions = :validity, :sys_period

      has_many :employees, temporal: true
    end
  end

  after { drop_all_tables }

  t = Time.utc(2000)

  build_records do
    {
      "Org" => {
        org: {id: 1, rev: 1, validity: t+0...nil, sys_period: t+0...}
      },
      "Employee" => {
        employee_av1_sv1: {id: 1, rev: 1, org_id: 1, salary: nil, validity: t+1...nil, sys_period: t+0...t+1},
        employee_av1_sv2: {id: 1, rev: 1, org_id: 1, salary: nil, validity: t+1...t+2, sys_period: t+1...t+3},
        employee_av2_sv1: {id: 1, rev: 2, org_id: 1, salary: 150, validity: t+2...nil, sys_period: t+1...t+2},
        employee_av2_sv2: {id: 1, rev: 2, org_id: 1, salary: 110, validity: t+2...nil, sys_period: t+2...t+3},
        employee_av1_sv3: {id: 1, rev: 1, org_id: 1, salary: nil, validity: t+1...t+3, sys_period: t+3...nil},
        employee_av2_sv3: {id: 1, rev: 2, org_id: 1, salary: 110, validity: t+3...nil, sys_period: t+3...nil}
      }
    }
  end

  it "temporal queries are applied" do
    expect(Employee.as_of(validity: t+1))
      .to contain_exactly(employee_av1_sv1, employee_av1_sv2, employee_av1_sv3)
    expect(Employee.as_of(sys_period: t+1))
      .to contain_exactly(employee_av1_sv2, employee_av2_sv1)
    expect(Employee.as_of(validity: t+1, sys_period: t+1))
      .to contain_exactly(employee_av1_sv2)
  end

  it "tags are applied" do
    expected_tags = {time_tags: {validity: t+1, sys_period: t+1}}

    expect(Employee.as_of(validity: t+1, sys_period: t+1))
      .to all(have_attributes(expected_tags))
  end

  it "temporal queries are applied through associations" do
    expect(Org.as_of(validity: t+1, sys_period: t+1).first.employees)
      .to contain_exactly(employee_av1_sv2)
  end

  it "tags are applied through associations" do
    expected_tags = {time_tags: {validity: t+1, sys_period: t+1}}

    org = Org.as_of(validity: t+1, sys_period: t+1).sole

    expect(org).to have_attributes(expected_tags)
    expect(org.employees).to all(have_attributes(expected_tags))
  end

  it "scopes the omitted temporal query to the current time on associations" do
    org_2 = Org.create!(id_value: 2, rev: 1, validity: t+0...nil, sys_period: t+0...nil)
    emp_2_av1_sv1 = org_2.employees.create!(id_value: 2, rev: 1, validity: t+0...t+2, sys_period: t+0...t+2)
    org_2.employees.create!(id_value: 2, rev: 1, validity: t+0...nil, sys_period: t+2...nil)

    org_as_of_t1 = Org.as_of(validity: t+0).find_by(id: 2)

    travel_to t+1 do
      employees = org_as_of_t1.employees

      expect(employees).to contain_exactly(emp_2_av1_sv1)
      expect(employees.sole.time_tags).to eq(validity: t+0)
    end
  end

  it "bitemporal querying" do
    [
      [
        employee_av1_sv1,
        employee_av1_sv2,
        employee_av2_sv1,
        employee_av2_sv2,
        employee_av1_sv3,
        employee_av2_sv3
      ],
      [],
      [employee_av1_sv1, employee_av1_sv2, employee_av1_sv3],
      [employee_av1_sv1, employee_av2_sv1, employee_av2_sv2, employee_av1_sv3],
      [employee_av1_sv1, employee_av2_sv1, employee_av2_sv2, employee_av2_sv3],

      [employee_av1_sv1],
      [],
      [employee_av1_sv1],
      [employee_av1_sv1],
      [employee_av1_sv1],

      [employee_av1_sv2, employee_av2_sv1],
      [],
      [employee_av1_sv2],
      [employee_av2_sv1],
      [employee_av2_sv1],

      [employee_av1_sv2, employee_av2_sv2],
      [],
      [employee_av1_sv2],
      [employee_av2_sv2],
      [employee_av2_sv2],

      [employee_av1_sv3, employee_av2_sv3],
      [],
      [employee_av1_sv3],
      [employee_av1_sv3],
      [employee_av2_sv3]
    ].each_with_index do |expected, index|
      sys_period = (index / 5) - 1
      validity = (index % 5) - 1

      time_dimensions = {}

      if sys_period > -1
        time_dimensions[:sys_period] = t+sys_period
      end

      if validity > -1
        time_dimensions[:validity] = t+validity
      end

      expect(Employee.as_of(time_dimensions))
        .to contain_exactly(*expected)
    end
  end
end

# rubocop:enable Layout/SpaceAroundOperators
