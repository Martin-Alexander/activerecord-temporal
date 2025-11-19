# Active Record Temporal

This gem is an Active Record plugin for temporal data modeling in PostgreSQL.

It provides both system versioning and application versioning. They can be used alone, in parallel, or in conjunction (e.g., for bitemporal data). Both systems use the same interface for time-travel queries.

## Why Temporal Data?

As applications mature, changing business requirements become increasingly complicated by the need to handle historical data. You might need to:

- Update subscription plans, but retain existing subscribers' original payment schedules
- Allow users to see information as it was before their view permission was revoked
- Understand why generated financial reports have changed recently
- Restore erroneously updated data

Many Rails applications use a patchwork of approaches:

- **Soft deletes** with a `deleted_at` column, but updates that still permanently overwrite data.
- **Audit gems or JSON columns** that serialize changes. Their data doesn't evolve with schema changes and cannot be easily integrated into Active Record queries, scopes, and associations.
- **Event systems** that are used to fill gaps in the data model and gradually take on responsibilities that are implementation details with no business relevance.

Temporal databases solve these problems by providing a simple and coherent data model to reach for whenever historical data is needed.

This can be a versioning strategy that operates automatically at the database level or one where versioning is used up front as the default method for all CRUD operations on a table.

## Requirements

- Active Record >= 8
- PostgreSQL >= 13

## Quick Start

```ruby
# Gemfile

gem "activerecord-temporal"
```

### Create a System Versioned Table

Create your regular `employees` table. For the `employees_history` table, add the `system_period` column and include it in the table's primary key. `#create_versioning_hook` is what enables system versioning.

```ruby
class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    enable_extension :btree_gist

    create_table :employees do |t|
      t.string :name
      t.integer :wage
    end

    create_table :employees_history, primary_key: [:id, :system_period] do |t|
      t.bigserial :id, null: false
      t.string :name
      t.integer :wage
      t.tstzrange :system_period, null: false
      t.exclusion_constraint "id WITH =, system_period WITH &&", using: :gist
    end

    create_versioning_hook :employees, :employees_history
  end
end
```

Create the namespace that all history models will exist in. If you're using Rails, I suggest you put this somewhere where it can be reloaded by Zeitwerk.

```ruby
module History
  include ActiveRecord::Temporal::HistoryModelNamespace
end
```

Include `ActiveRecord::Temporal` and enable system versioning.

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include ActiveRecord::Temporal

  system_versioning
end
```

Call `system_versioned` on the model that now has a system versioned table.

```ruby
class Employee < ApplicationRecord
  system_versioned
end
```

Manipulate data as normal and use the time-travel query interface to read data as it was at any time in the past.

```ruby
Employee.create(name: "Sam", wage: 75)        # Executed on 1999-12-31
bob = Employee.create(name: "Bob", wage: 100) # Executed on 2000-01-07
bob.update(wage: 200)                         # Executed on 2000-01-14
bob.destroy                                   # Executed on 2000-01-28

Employee.history
# => [
#   #<History::Employee id: 1, name: "Sam", wage: 75, system_period: 1999-12-31...>,
#   #<History::Employee id: 2, name: "Bob", wage: 100, system_period: 2000-01-07...2000-01-14>,
#   #<History::Employee id: 2, name: "Bob", wage: 200, system_period: 2000-01-14...2000-01-28>
# ]

Employee.history.as_of(Time.parse("2000-01-10"))
# => [
    #<History::Employee id: 1, name: "Sam", wage: 75, system_period: 1999-12-31...>,
    #<History::Employee id: 2, name: "Bob", wage: 100, system_period: 2000-01-07...2000-01-14>
# ]
```

#### Read more
 - [Time-travel Queries Interface](#time-travel-queries-interface)
 - [System Versioning](#system-versioning)
 - [History Model Namespace](#history-model-namespace)

### Create an Application Versioned Table

Create an `employees` table with a `version` column in the primary key and a `tstzrange` column to be the time dimension.

```ruby
class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    enable_extension :btree_gist

    create_table :employees, primary_key: [:id, :version] do |t|
      t.bigserial :id, null: false
      t.bigint :version, null: false, default: 1
      t.string :name
      t.integer :wage
      t.tstzrange :validity, null: false
      t.exclusion_constraint "id WITH =, validity WITH &&", using: :gist
    end
  end
end
```

Include `ActiveRecord::Temporal` and enable application versioning for the column you're using as the time dimension.

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include ActiveRecord::Temporal

  application_versioning dimensions: :validity
end
```

Call `application_versioned` on the model that is application versioned.

```ruby
class Employee < ActiveRecord::Base
  application_versioned
end
```

`::originate_at`, `#revise_at` and `#inactive_at` are the versioning equivalents of `::create`, `#update`, `#destroy`. `::original_at` and `#revision_at` are the non-saving variants.

```ruby
travel_to Time.parse("2000-01-01")

Employee.originate_at(1.month.from_now).with(wage: 75)
Employee.originate_at(1.month.from_now).with(wage: 100)
employee = Employee.last
new_version = employee.revise_at(2.months.from_now).with(wage: 200)
new_version.inactive_at(1.year.from_now)

Employee.all
# => [
#   #<Employee id: 1, version: 1, wage: 75, validity: 2000-02-01...>,
#   #<Employee id: 2, version: 1, wage: 100, validity: 2000-02-01...2000-03-01>,
#   #<Employee id: 2, version: 2, wage: 200, validity: 2000-03-01...2001-01-01>
# ]

Employee.as_of(Time.parse("2000-02-15"))
# => [
#   #<Employee id: 1, version: 1, wage: 75, validity: 2000-02-01...>,
#   #<Employee id: 2, version: 1, wage: 100, validity: 2000-02-01...2000-03-01>
#]
```

#### Read more
 - [Time-travel Queries Interface](#time-travel-queries-interface)
 - [Application Versioning](#application-versioning)
 - [Foreign Key Constraints](#foreign-key-constraints)

### Make Time-travel Queries

This interface works the same with system versioning and application. But this example assumes at least the `Product` and `Order` models are system versioned:

```ruby
product = Product.create(price: 50)
order = Order.create(placed_at: Time.current)
order.line_items.create(product: product)

Product.first.update(price: 100)            # Product catalogue changed

# Get the order's original price
order = Order.first
order.products.first                        # => #<Product price: 100>
order.as_of(order.placed_at).products.first # => #<History::Product price: 50>

products = Product
  .as_of(10.months.ago)
  .includes(line_items: :order)
  .where(line_items: {quantity: 1})              # => [#<History::Product>, #<History::Product>]
```

Records from time-travel queried are tagged with the time passed to `#as_of` and will propagate the time-travel query to subsequent associations.

```ruby
products.first.categories.first             # => The product's category as it was 10 months ago
```

`temporal_scoping` implicitly sets all queries in the block to be as of the given time.

```ruby
include ActiveRecord::Temporal::Scoping

temporal_scoping.at 1.year.ago do
  products = Product.all                    # => All products as of 1 year ago
  products = Product.as_of(Time.current)    # Opt-in to ignore the scope's default time
end
```

#### Read more
 - [Time-travel Queries Interface](#time-travel-queries-interface)
 - [Temporal Associations](#temporal-associations)

## System Versioning

The temporal model of this gem is based on the SQL specification. It's also roughly the same model used by RDMSs like [MariaDB](https://mariadb.com/docs/server/reference/sql-structure/temporal-tables/system-versioned-tables) and [Microsoft SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables?view=sql-server-ver17). It's also used by the [Temporal Table](https://github.com/arkhipov/temporal_tables) PostgreSQL extension. The triggers used in this gem are inspired by [PL/pgSQL version of Temporal Tables](https://github.com/nearform/temporal_tables).

Rows in the history table (or partition, view, etc.) represent rows that existed in the source table over a particular period of time. For PostgreSQL implementations this period of time is typically stored in a `tstzrange` column that this gem calls `system_period`.

### Inserts

Rows inserted into the source table will be also inserted into the history table with `system_period` beginning at the current time and ending at infinity.

```sql
-- Transaction start time: 2000-01-01

INSERT INTO products (name, price) VALUES ('Glow & Go Set', 29900), ('Zepbound', 34900)

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 29900 │
│  2 │ Zepbound      │ 34900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬──────────────────────────────────┐
│ id │     name      │ price │          system_period           │
├────┼───────────────┼───────┼──────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00",infinity) │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00",infinity) │
└────┴───────────────┴───────┴──────────────────────────────────┘*/
```

### Updates

Rows updated in the source table will:

1. Update the matching row in the history table by ending `system_period` with the current time.
2. Insert a row into the history table that matches the new state in the source table and beginning `system_period` at the current time and ending at infinity.

```sql
-- Transaction start time: 2000-01-02

UPDATE products SET price = 14900 WHERE id = 1

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 14900 │
│  2 │ Zepbound      │ 34900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬───────────────────────────────────────────────┐
│ id │     name      │ price │                 system_period                 │
├────┼───────────────┼───────┼───────────────────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00","2000-01-02 00:00:00") │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00",infinity)              │
│  1 │ Glow & Go Set │ 14900 │ ["2000-01-02 00:00:00",infinity)              │
└────┴───────────────┴───────┴───────────────────────────────────────────────┘*/
```

### Deletes

Rows deleted in the source table will update the matching row in the history table by ending `system_period` with the current time.

```sql
-- Transaction start time: 2000-01-03

DELETE FROM products WHERE id = 2

/* products
┌────┬───────────────┬───────┐
│ id │     name      │ price │
├────┼───────────────┼───────┤
│  1 │ Glow & Go Set │ 14900 │
└────┴───────────────┴───────┘*/

/* products_history
┌────┬───────────────┬───────┬───────────────────────────────────────────────┐
│ id │     name      │ price │                 system_period                 │
├────┼───────────────┼───────┼───────────────────────────────────────────────┤
│  1 │ Glow & Go Set │ 29900 │ ["2000-01-01 00:00:00","2000-01-02 00:00:00") │
│  2 │ Zepbound      │ 34900 │ ["2000-01-01 00:00:00","2000-01-03 00:00:00") │
│  1 │ Glow & Go Set │ 14900 │ ["2000-01-02 00:00:00",infinity)              │
└────┴───────────────┴───────┴───────────────────────────────────────────────┘*/
```

### Schema Migrations

```ruby
class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    enable_extension :btree_gist

    create_table :products do |t|
      t.string :name, null: false
      t.index :sku, unique: true
      t.integer :price
    end

    create_table :products_history, primary_key: [:id, :system_period] do |t|
      t.bigint :id, null: false
      t.string :name
      t.integer :price
      t.tstzrange :system_period, null: false
      t.exclusion_constraint "id WITH =, system_period WITH &&", using: :gist
    end

    create_versioning_hook :products,           # Enables system versioning for all columns
      :products_history                         # in the source table

    create_versioning_hook :products,           # But the history table doesn't track `sku` so
      :products_history,                        # we need explicitly set the columns to
      columns: [:id, :name, :price]             # exclude it

    add_column :products_history, :sku, :string # We can add `sku` to the history table later

    change_versioning_hook :products,           # And update the triggers to start tracking it
      :products_history,
      add_columns: [:sku]

    change_versioning_hook :products,           # Keep the `name` column, but stop tracking it
      :products_history,
      remove_columns: [:name]

    drop_versioning_hook :products,             # Keep the table, but disable system versioning
      :products_history

    drop_versioning_hook :products,             # Include options to make it reversible
      :products_history,
      columns: [:id, :sku, :price]

    drop_table :products_history                # Drop history table like any other table

    create_versioning_hook :products,           # If the products table used something other
      :products_history,                        # than `id` for the primary key
      columns: [:id, :name, :price]
      primary_key: [:uuid]
  end
end
```

The only strict requirements for a history table are:
1. It must have a `tstzrange` column called `system_period`
2. Its primary key must contain all primary key columns of the source table plus `system_period`
3. All columns shared by the two tables must have the same type

Very likely though you'll also want to make sure that it doesn't have any unique indexes or non-temporal foreign key constraints.

Enabling the `btree_gist` extension allows you to use an efficient exclusion constraint to prevent records with the same ID from having overlapping `system_period` columns.

`#create_versioning_hook` enables system versioning by creating three triggers that automatically updating the history table whenever the source table changes.

### History Model Namespace

System versioning works by creating a parallel hierarchy of history models for your regular models. This applies to all models in the hierarchy whether they're system versioned or not and allows you to make queries that join multiple tables.

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include ActiveRecord::Temporal

  system_versioning
end

# ✅ System versioned
class Product < ApplicationRecord
  system_versioned

  has_many :line_items
end

# ❌ Not system versioned
class LineItem < ApplicationRecord
  belongs_to :product
end

module History
  include Temporal::SystemVersioningNamespace
end

History::Product                   # => History::Product(id: integer, system_period: tstzrange, name: string)
History::LineItem                  # => History::LineItem(id: integer, product_id: integer, order_id: integer)

History::Product.table_name        # => "products_history"
History::LineItem.table_name       # => "line_items"

History::Product.primary_key       # => ["id", "system_period"]
History::LineItem.primary_key      # => "id"

Product.history                    # [History::Product, ...]
LineItem.history                   # [LineItem::Product, ...]

products = Product.history.as_of(Time.parse("2027-12-23"))
product = products.first           # => #<History::Product id: 70, system_period: 2027-11-07...2027-12-28, name: "Toy">
product.name                       # => "Toy"
product.line_items                 # => []

products = Product.history.as_of(Time.parse("2028-01-03"))
product = products.first           # => #<History::Product id: 1, system_period: 2027-12-28..., name: "Toy (NEW!)">
product.name                       # => "Toy (NEW!)"
product.line_items                 # => [#<History::LineItem id: 1, product_id: 70, order_id: 4>]
```

By default, calling `system_versioning` will look for a namespace called `History`. But this can be configured.

```ruby
module Versions
  include Temporal::SystemVersioningNamespace
end

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include ActiveRecord::Temporal

  system_versioning

  def self.history_model_namespace
    Versions
  end
end
```

By default, the namespace will only provide history models for models in the root namespace that descend from the root model where `system_versioning` was called (`ApplicationRecord` in this case).

```ruby
module History
  include Temporal::SystemVersioningNamespace

  namespace "Tenant"

  namespace "Backend" do
    namespace "Admin"
  end
end

Tenant::Product.history          # => [History::Tenant::Product, ...]
Backend::Config.history          # => [History::Backend::Config, ...]
Backend::Admin::Customer.history # => [History::Backend::Admin::Customer, ...]
```

## Application Versioning

```ruby
class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    enable_extension :btree_gist

    create_table :employees, primary_key: [:id, :version] do |t|
      t.bigserial :id, null: false
      t.bigint :version, null: false, default: 1
      t.string :name
      t.integer :price
      t.tstzrange :validity, null: false
      t.exclusion_constraint "id WITH =, validity WITH &&", using: :gist
    end
  end
end

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include ActiveRecord::Temporal

  application_versioning dimensions: :validity
end

class Product < ApplicationRecord
  application_versioned
end
```

The only strict requirements for a application versioned table are:
1. It must have a `tstzrange` column (name doesn't matter)
2. It must have a numeric `version` column with a default value

The `version` column will be automatically incremented when creating new versions in `#after_initialize_revision`.

This method can be defined in the model to for additional behaviour. Don't forget to call `super`.

```ruby
class Product < ApplicationRecord
  application_versioned

  def after_initialize_revision(prev_version)
    super

    # Some custom post-initialization logic
  end
end
```

### Versioning Interface

`::original_at` instantiates a first version at the given time.

`::originate_at` does the same, but also saves it.

```ruby
travel_to Time.parse("2000-01-01") # Lock `Time.current` at 2000-01-01

prod_v1 = Product.original_at(1.year.from_now).with(price: 100)
# => #<Product id: nil, version: 1, price: 100, validity: 2001-01-01...>

prod_v1.persisted? # => false

prod_v1 = Product.originate_at(1.year.from_now).with(price: 100)
# => #<Product id: 1, version: 1, price: 55, validity: 2001-01-01...>

prod_v1.persisted? # => true
```

`#revision_at` instantiates the next version of a record at the given time.

```ruby
prod_v2 = prod_v1.revision_at(2.years.from_now).with(price: 250)
# => #<Product id: 1, version: 2, price: 250, validity: 2002-01-01...>

prod_v1
# => #<Product id: 1, version: 1, price: 100, validity: 2001-01-01...2001-01-01>

prod_v1.save # => true
prod_v2.save # => true
```

`#revise_at` does the same thing, but also saves it.

```ruby
prod_v3 = prod_v2.revise_at(3.years.from_now).with(price: 500)
# => #<Product id: 1, version: 3, price: 500, validity: 2003-01-01...>

prod_v2
# => #<Product id: 1, version: 2, price: 250, validity: 2002-01-01...2003-01-01>

prod_v2.persisted? # => true
prod_v3.persisted? # => true
```

`#inactive_at` closes the record's time dimension at the given time, making it the last version.

```ruby
prod_v3.inactivate_at(4.years.from_now)
# => #<Product id: 1, version: 3, price: 500, validity: 2003-01-01...2004-01-01>
```

All the above methods have a counterpart without `_at` that default to the current time or the time of enclosing scoped block.

```ruby
travel_to Time.parse("2030-01-01") # Lock `Time.current` at 2030-01-01

prod_v1 = Product.find_by(id: 1, version: 1)

prod_v2 = prod_v1.revise.with(price: 1000)
# => #<Product id: 1, version: 2, price: 1000, validity: 2030-01-01...>

include ActiveRecord::Temporal::Scoping

temporal_scoping.at 5.years.from_now do
  prod_v2.inactivate
end
# => #<Product id: 1, version: 2, price: 1000, validity: 2030-01-01...2035-01-01>
```

## Time-Travel Queries Interface

The time-travel query interface behaves the same for application and system versioned models.

`at_time` is an Active Record scope that filters rows by time. It applies to the base model as well as all preloaded/joined associations. 

```ruby
Product.at_time(Time.parse("2025-01-01"))
```
```sql
SELECT products.* FROM products WHERE products.validity @> '2025-01-01 00:00:00'::timestamptz
```

```ruby
Product.at_time(Time.parse("2025-01-01"))
  .includes(line_items: :order)
  .where(orders: {status: "shipped"})
```
```sql
SELECT products.* FROM products
JOIN line_items ON line_items.product_id = products.id
  AND line_items.validity @> '2025-01-01 00:00:00'::timestamptz
JOIN orders ON orders.id = line_items.order_id
  AND orders.validity @> '2025-01-01 00:00:00'::timestamptz
WHERE products.validity @> '2025-01-01 00:00:00'::timestamptz AND orders.status = 'shipped'
```

`as_of` is another Active Record scope. It applies the same filtering behaviour as `at_time` but also tags all loaded records with the time used such that any subsequent associations called on them will propagate the `as_of` scope.

```ruby
product = Product.as_of(Time.parse("2025-01-01")).first
# => #<Product id: 1, version: 2, price: 1000, validity: 2030-01-01...>

product.time_tag               # => 2025-01-01

product.line_items.first.order # => Order as it was at 2025-01-01
```

`#as_of(time)` returns a new instance of a record at the given time. Returns nil if record does not exist at that time.

`#as_of!(time)` reloads the record to the version at the given time. Raises error if record does not exist at that time.

```ruby
product = Product.first

product.time_tag               # => nil
product.line_items             # => [LineItem] as they are now

product.as_of!(Time.parse("2025-01-01"))

product.time_tag               # => 2025-01-01
product.line_items             # => [LineItem] as they were at 2025-01-01
```

The time-travel query interface doesn't require any type of versioning at all. As long as a model has a `tstzrange` column, includes `ActiveRecord::Temporal::Querying` and declares the time dimension.

```ruby
create_table :employees do |t|
  t.tstzrange :effective_period
end

class Employee < ActiveRecord::Base
  include ActiveRecord::Temporal::Querying

  self.time_dimensions = :effective_period
end

Employee.as_of(Time.current) # => [Employee, Employee]
```

### Scoped Blocks

Inside of a time-scoped block all query will by default have the `at_time` scope applied. It can be overwritten.

```ruby
include ActiveRecord::Temporal::Scoping

temporal_scoping.at Time.parse("2011-04-30") do
  Product.all                     # => All products as of 2011-04-30
  Product.first.prices            # => All associated prices as of 2011-04-30
  Product.as_of(Time.current)     # => All current products

  temporal_scoping.at Time.parse("1990-06-07") do
    Product.all                   # => All products as of 1990-06-07
  end
end
```

### Temporal Associations

For `at_time` and `as_of` to filter associated models the associations between models must be passed the `temporal: true` option.

```ruby
class Product < ApplicationRecord
  application_versioned

  has_many :line_items
  has_many :orders, through: :line_items
end
```

By default, this query will filter products by the time, but not the line items or orders.

```ruby
Product.at_time(Time.parse("2025-01-01"))
  .includes(line_items: :order)
  .where(orders: {status: "shipped"})
```

You must add `temporal: true` to the associations. Then the entire query will be temporal.

```ruby
class Product < ApplicationRecord
  application_versioned

  has_many :line_items, temporal: true
  has_many :orders, through: :line_items, temporal: true
end
```

Associated models do not need to be application versioned or system versioned to use temporal associations. If they're used in a query with `at_time` or `as_of` they will behave as though all their rows have double unbounded time ranges equivalent to `nil...nil` in Ruby or `['-infinity','infinity')` PostgreSQL.

The history models automatically generated when using system versioning will automatically have all their associations temporalized whether they're backed by a history table or not.

#### Interaction with Scoped Blocks

By their nature, temporal associations will always filter associated records by the current time or the time of the scoped block.

```ruby
Product.all             # => All product versions, past, present, and future
LineItem.first.products # => associated products scoped to the current time
```

If you typically only need current records, you can scope controller actions to `Time.current`, which roughly equates to the time when a request was received.

```ruby
class ApplicationController < ActionController::Base
  include ActiveRecord::Temporal::Scoping

  around_action do |controller, action|
    temporal_scoping.at(Time.current, &action)
  end
end
```

`default_scope` can also be used to achieve a similar effect.

```ruby
class ApplicationRecord < ActiveRecord::Base
  include ActiveRecord::Temporal

  application_versioned

  self.time_dimensions = :validity

  default_scope -> { at_time(Time.current) }
end
```

#### Compatibility with Existing Scopes

```ruby
class Product < ActiveRecord::Base
  application_versioned

  has_one :price, -> { where(active: true) }, temporal: true
end
```

Temporal associations are implemented as association scopes and will be merged with the association's non-temporal scope.

## Foreign Key Constraints

Active Record models typically have a single column primary key called `id`. History tables must have a composite primary key, and though not a requirement it's recommended that application versioned tables do as well.

Furthermore, you probably don't want foreign key constraints to reference a single row in a versioned table. A book should belong to an author, not a specific version of that author. But standard foreign key constraints must reference columns that uniquely identify a row.

There are two options to get around this:
1. Use the `WITHOUT OVERLAPS`/`PERIOD` feature added in PostgreSQL 18 that allows for temporal foreign key constraints
2. Implement effective foreign key constraints using triggers
