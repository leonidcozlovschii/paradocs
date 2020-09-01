# Paradocs: Extended [Parametric gem](https://github.com/ismasan/parametric) + Documentation Generation

![Ruby](https://github.com/mtkachenk0/paradocs/workflows/Ruby/badge.svg)

Declaratively define data schemas in your Ruby objects, and use them to whitelist, validate or transform inputs to your programs.

Useful for building self-documeting APIs, search or form objects. Or possibly as an alternative to Rails' _strong parameters_ (it has no dependencies on Rails and can be used stand-alone).
## Installation
```sh
$ gem install paradocs
```

Or with Bundler in your Gemfile.
```rb
gem 'paradocs'
```

## Getting Started

Define a schema

```ruby
schema = Paradocs::Schema.new do
  field(:title).type(:string).present
  field(:status).options(["draft", "published"]).default("draft")
  field(:tags).type(:array)
end
```

Populate and use. Missing keys return defaults, if provided.

```ruby
form = schema.resolve(title: "A new blog post", tags: ["tech"])

form.output # => {title: "A new blog post", tags: ["tech"], status: "draft"}
form.errors # => {}
```

Undeclared keys are ignored.

```ruby
form = schema.resolve(foobar: "BARFOO", title: "A new blog post", tags: ["tech"])

form.output # => {title: "A new blog post", tags: ["tech"], status: "draft"}
```

Validations are run and errors returned


```ruby
form = schema.resolve({})
form.errors # => {"$.title" => ["is required"]}
```

If options are defined, it validates that value is in options

```ruby
form = schema.resolve({title: "A new blog post", status: "foobar"})
form.errors # => {"$.status" => ["expected one of draft, published but got foobar"]}
```

## Nested schemas

A schema can have nested schemas, for example for defining complex forms.

```ruby
person_schema = Paradocs::Schema.new do
  field(:name).type(:string).required
  field(:age).type(:integer)
  field(:friends).type(:array).schema do
    field(:name).type(:string).required
    field(:email).policy(:email)
  end
end
```

It works as expected

```ruby
results = person_schema.resolve(
  name: "Joe",
  age: "38",
  friends: [
    {name: "Jane", email: "jane@email.com"}
  ]
)

results.output # => {name: "Joe", age: 38, friends: [{name: "Jane", email: "jane@email.com"}]}
```

Validation errors use [JSON path](http://goessner.net/articles/JsonPath/) expressions to describe errors in nested structures

```ruby
results = person_schema.resolve(
  name: "Joe",
  age: "38",
  friends: [
    {email: "jane@email.com"}
  ]
)

results.errors # => {"$.friends[0].name" => "is required"}
```

## Built-in policies

Type coercions (the `type` method) and validations (the `validate` method) are all _policies_.

Paradocs ships with a number of built-in policies.

### :string

Calls `:to_s` on the value

```ruby
field(:title).type(:string)
```

### :integer

Calls `:to_i` on the value

```ruby
field(:age).type(:integer)
```

### :number

Calls `:to_f` on the value

```ruby
field(:price).type(:number)
```

### :boolean

Returns `true` or `false` (`nil` is converted to `false`).

```ruby
field(:published).type(:boolean)
```

### :datetime

Attempts parsing value with [Datetime.parse](http://ruby-doc.org/stdlib-2.3.1/libdoc/date/rdoc/DateTime.html#method-c-parse). If invalid, the error will be added to the output's `errors` object.

```ruby
field(:expires_on).type(:datetime)
```

### :format

Check value against custom regexp

```ruby
field(:salutation).policy(:format, /^Mr\/s/)
# optional custom error message
field(:salutation).policy(:format, /^Mr\/s\./, "must start with Mr/s.")
```

### :email

```ruby
field(:business_email).policy(:email)
```

### :required

Check that the key exists in the input.

```ruby
field(:name).required

# same as
field(:name).policy(:required)
```

Note that _required_ does not validate that the value is not empty. Use _present_ for that.

### :present

Check that the key exists and the value is not blank.

```ruby
field(:name).present

# same as
field(:name).policy(:present)
```

If the value is a `String`, it validates that it's not blank. If an `Array`, it checks that it's not empty. Otherwise it checks that the value is not `nil`.

### :declared

Check that a key exists in the input, or stop any further validations otherwise.
This is useful when chained to other validations. For example:

```ruby
field(:name).declared.present
```

The example above will check that the value is not empty, but only if the key exists. If the key doesn't exist no validations will run.

### :gt

Validate that the value is greater than a number

```ruby
field(:age).policy(:gt, 21)
```

### :lt

Validate that the value is less than a number

```ruby
field(:age).policy(:lt, 21)
```

### :options

Pass allowed values for a field

```ruby
field(:status).options(["draft", "published"])

# Same as
field(:status).policy(:options, ["draft", "published"])
```

### :length

Specify value's length constraints
 - `min:` - The attribute cannot have less than the specified length.
 - `max`  - The attribute cannot have more than the specified length.
 - `eq`   - The attribute should be exactly equal to the specified length.

```ruby
field(:name).length(min: 5, max: 25)
field(:name).length(eq: 10)
```

### :split

Split comma-separated string values into an array.
Useful for parsing comma-separated query-string parameters.

```ruby
field(:status).policy(:split) # turns "pending,confirmed" into ["pending", "confirmed"]
```

## Custom policies

You can also register your own custom policy objects. A policy can be not inherited from `Paradocs::BasePolicy`, in this case it must implement the following methods: `#valid?`, `#coerce`, `#message`, `#meta_data`, `#policy_name`

```ruby
class MyPolicy < Paradocs::BasePolicy
  # Validation error message, if invalid
  def message
    'is invalid'
  end

  # Whether or not to validate and coerce this value
  # if false, no other policies will be run on the field
  def eligible?(value, key, payload)
    true
  end

  # Transform the value
  def coerce(value, key, context)
    value
  end

  # Is the value valid?
  def validate(value, key, payload)
    true
  end

  # merge this object into the field's meta data
  def meta_data
    {type: :string}
  end
end
```


You can register your policy with:

```ruby
Paradocs.policy :my_policy, MyPolicy
```

And then refer to it by name when declaring your schema fields

```ruby
field(:title).policy(:my_policy)
```

You can chain custom policies with other policies.

```ruby
field(:title).required.policy(:my_policy)
```

Note that you can also register instances.

```ruby
Paradocs.policy :my_policy, MyPolicy.new
```

For example, a policy that can be configured on a field-by-field basis:

```ruby
class AddJobTitle
  def initialize(job_title)
    @job_title = job_title
  end

  def message
    'is invalid'
  end

  # Noop
  def eligible?(value, key, payload)
    true
  end

  # Add job title to value
  def coerce(value, key, context)
    "#{value}, #{@job_title}"
  end

  # Noop
  def validate(value, key, payload)
    true
  end

  def meta_data
    {}
  end
end

# Register it
Paradocs.policy :job_title, AddJobTitle
```

Now you can reuse the same policy with different configuration

```ruby
manager_schema = Paradocs::Schema.new do
  field(:name).type(:string).policy(:job_title, "manager")
end

cto_schema = Paradocs::Schema.new do
  field(:name).type(:string).policy(:job_title, "CTO")
end

manager_schema.resolve(name: "Joe Bloggs").output # => {name: "Joe Bloggs, manager"}
cto_schema.resolve(name: "Joe Bloggs").output # => {name: "Joe Bloggs, CTO"}
```

## Custom policies, short version

For simple policies that don't need all policy methods, you can:

```ruby
Paradocs.policy :cto_job_title do
  coerce do |value, key, context|
    "#{value}, CTO"
  end
end

# use it
cto_schema = Paradocs::Schema.new do
  field(:name).type(:string).policy(:cto_job_title)
end
```

```ruby
Paradocs.policy :over_21_and_under_25 do
  coerce do |age, key, context|
    age.to_i
  end

  validate do |age, key, context|
    age > 21 && age < 25
  end
end
```

## Cloning schemas

The `#clone` method returns a new instance of a schema with all field definitions copied over.

```ruby
new_schema = original_schema.clone
```

New copies can be further manipulated without affecting the original.

```ruby
# See below for #policy and #ignore
new_schema = original_schema.clone.policy(:declared).ignore(:id) do |sc|
  field(:another_field).present
end
```

## Merging schemas

The `#merge` method will merge field definitions in two schemas and produce a new schema instance.

```ruby
basic_user_schema = Paradocs::Schema.new do
  field(:name).type(:string).required
  field(:age).type(:integer)
end

friends_schema = Paradocs::Schema.new do
  field(:friends).type(:array).schema do
    field(:name).required
    field(:email).policy(:email)
  end
end

user_with_friends_schema = basic_user_schema.merge(friends_schema)

results = user_with_friends_schema.resolve(input)
```

Fields defined in the merged schema will override fields with the same name in the original schema.

```ruby
required_name_schema = Paradocs::Schema.new do
  field(:name).required
  field(:age)
end

optional_name_schema = Paradocs::Schema.new do
  field(:name)
end

# This schema now has :name and :age fields.
# :name has been redefined to not be required.
new_schema = required_name_schema.merge(optional_name_schema)
```

## #meta

The `#meta` field method can be used to add custom meta data to field definitions.
These meta data can be used later when instrospecting schemas (ie. to generate documentation or error notices).

```ruby
create_user_schema = Paradocs::Schema.new do
  field(:name).required.type(:string).meta(label: "User's full name")
  field(:status).options(["published", "unpublished"]).default("published")
  field(:age).type(:integer).meta(label: "User's age")
  field(:friends).type(:array).meta(label: "User friends").schema do
    field(:name).type(:string).present.meta(label: "Friend full name")
    field(:email).policy(:email).meta(label: "Friend's email")
  end
end
```

### Subschemas and mutations.
Sometimes depending on the data the structure may vary. Most frequently used option is to use `:declared` policy (a.k.a. conditional, but below is another option:

- Mutations are blocks that are assigned to a field and called during the validation (in #resolve), block receives all the related data and should return a subschema name.
- Subschemas are conditional schemas declared inside schemas. They doesn't exist until mutation block is called and decides to invoke a subschema.
```ruby
person_schema = Paradocs::Schema.new do
  field(:role).type(:string).options(["admin", "user"]).mutates_schema! do |value, key, payload, env|
    value == :admin ? :admin_schema : :user_schema
  end

  subschema(:admin_schema) do
    field(:permissions).present.type(:string).options(["superuser"])
    field(:admin_field)
  end
  subschema(:user_schema) do
    field(:permissions).present.type(:string).options(["readonly"])
    field(:user_field)
  end
end

results = person_schema.resolve(name: "John", age: 20, role: :admin, permissions: "superuser")
results.output # => {name: "John", age: 20, role: :admin, permissions: "superuser", admin_field: nil}
results = person_schema.resolve(name: "John", age: 20, role: :admin, permissions: "readonly")
results.errors => {"$.permissions"=>["must be one of superuser, but got readonly"]}
```

### Reusing nested schemas

You can optionally use an existing schema instance as a nested schema:

```ruby
friends_schema = Paradocs::Schema.new do
  field(:friends).type(:array).schema do
    field(:name).type(:string).required
    field(:email).policy(:email)
  end
end

person_schema = Paradocs::Schema.new do
  field(:name).type(:string).required
  field(:age).type(:integer)
  # Nest friends_schema
  field(:friends).type(:array).schema(friends_schema)
end
```

## Structures
### #structure

A `Schema` instance has a `#structure` method that allows instrospecting schema meta data.

```ruby
create_user_schema.structure[:name][:label] # => "User's full name"
create_user_schema.structure[:age][:label] # => "User's age"
create_user_schema.structure[:friends][:label] # => "User friends"
# Recursive schema structures
create_user_schema.structure => {
  _errors: [],
  _subschemes: {},
  name: {
    required: true,
    type: :string,
    label: "User's full name"
  },
  status: {
    options: ["published", "unpublished"],
    default: "published"
  },
  age: {
    type: :integer,
    label: "User's age"
  },
  friends: {
    type: :array,
    label: "User friends",
    structure: {
      _subschemes: {},
      name: {
        type: :string,
        required: true,
        present: true,
        label: "Friend full name"
      },
      email: {label: "Friend's email"}
    }
  }
}
```

Note that many field policies add field meta data.

```ruby
create_user_schema.structure[:name][:type] # => :string
create_user_schema.structure[:name][:required] # => true
create_user_schema.structure[:status][:options] # => ["published", "unpublished"]
create_user_schema.structure[:status][:default] # => "published"
```
## #flatten_structure
 A `Schema` instance also has a `#flatten_structure` method that allows instrospecting schema meta data without deep nesting.
```rb
{
  _errors: [],
  _subschemes: {},
  "name"=>{
    required: true,
    type: :string,
    label: "User's full name",
    json_path: "$.name"
  },
  "status"=>{
    options: ["published", "unpublished"],
    default: "published",
    json_path: "$.status"
  },
  "age"=>{
    type: :integer,
    label: "User's age", :json_path=>"$.age"
  },
  "friends"=>{
    type: :array,
    label: "User friends",
    json_path: "$.friends"
  },
  "friends.name"=>{
    type: :string,
    required: true,
    present: true,
    label: "Friend full name",
    json_path: "$.friends.name"
  },
  "friends.email"=>{
    label: "Friend's email",
    json_path: "$.friends.email"
  }
}
```

## #walk

The `#walk` method can recursively walk a schema definition and extract meta data or field attributes.

```ruby
schema_documentation = create_user_schema.walk do |field|
  {type: field.meta_data[:type], label: field.meta_data[:label]}
end.output

# Returns

{
  name: {type: :string, label: "User's full name"},
  age: {type: :integer, label: "User's age"},
  status: {type: :string, label: nil},
  friends: [
    {
      name: {type: :string, label: "Friend full name"},
      email: {type: nil, label: "Friend email"}
    }
  ]
}
```

When passed a _symbol_, it will collect that key from field meta data.

```ruby
schema_labels = create_user_schema.walk(:label).output

# returns

{
  name: "User's full name",
  age: "User's age",
  status: nil,
  friends: [
    {name: "Friend full name", email: "Friend email"}
  ]
}
```

Potential uses for this are generating documentation (HTML, or [JSON Schema](http://json-schema.org/), [Swagger](http://swagger.io/), or maybe even mock API endpoints with example data.

## Form objects DSL

You can use schemas and fields on their own, or include the `DSL` module in your own classes to define form objects.

```ruby
require "parametric/dsl"

class CreateUserForm
  include Paradocs::DSL

  schema(:test) do
    field(:name).type(:string).required
    field(:email).policy(:email).required
    field(:age).type(:integer)
    subschema_by(:age) { |age| age > 18 ? :allow : :deny }
  end

  subschema_for(:test, name: :allow) { field(:role).options(["sign_in"]) }
  subschema_for(:test, name: :deny) { field(:role).options([]) }

  attr_reader :params, :errors

  def initialize(input_data)
    results = self.class.schema.resolve(input_data)
    @params = results.output
    @errors = results.errors
  end

  def run!
    if !valid?
      raise InvalidFormError.new(errors)
    end

    run
  end

  def valid?
    !errors.any?
  end

  private

  def run
    User.create!(params)
  end
end
```

Form schemas can also be defined by passing another form or schema instance. This can be useful when building form classes in runtime.

```ruby
UserSchema = Paradocs::Schema.new do
  field(:name).type(:string).present
  field(:age).type(:integer)
end

class CreateUserForm
  include Paradocs::DSL
  # copy from UserSchema
  schema UserSchema
end
```

### Form object inheritance

Sub classes of classes using the DSL will inherit schemas defined on the parent class.

```ruby
class UpdateUserForm < CreateUserForm
  # All field definitions in the parent are conserved.
  # New fields can be defined
  # or existing fields overriden
  schema do
    # make this field optional
    field(:name).declared.present
  end

  def initialize(user, input_data)
    super input_data
    @user = user
  end

  private
  def run
    @user.update params
  end
end
```

### Schema-wide policies

Sometimes it's useful to apply the same policy to all fields in a schema.

For example, fields that are _required_ when creating a record might be optional when updating the same record (ie. _PATCH_ operations in APIs).

```ruby
class UpdateUserForm < CreateUserForm
  schema.policy(:declared)
end
```

This will prefix the `:declared` policy to all fields inherited from the parent class.
This means that only fields whose keys are present in the input will be validated.

Schemas with default policies can still define or re-define fields.

```ruby
class UpdateUserForm < CreateUserForm
  schema.policy(:declared) do
    # Validation will only run if key exists
    field(:age).type(:integer).present
  end
end
```

### Ignoring fields defined in the parent class

Sometimes you'll want a child class to inherit most fields from the parent, but ignoring some.

```ruby
class CreateUserForm
  include Paradocs::DSL

  schema do
    field(:uuid).present
    field(:status).required.options(["inactive", "active"])
    field(:name)
  end
end
```

The child class can use `ignore(*fields)` to ignore fields defined in the parent.

```ruby
class UpdateUserForm < CreateUserForm
  schema.ignore(:uuid, :status) do
    # optionally add new fields here
  end
end
```

## Schema options

Another way of modifying inherited schemas is by passing options.

```ruby
class CreateUserForm
  include Paradocs::DSL

  schema(default_policy: :noop) do |opts|
    field(:name).policy(opts[:default_policy]).type(:string).required
    field(:email).policy(opts[:default_policy).policy(:email).required
    field(:age).type(:integer)
  end

  # etc
end
```

The `:noop` policy does nothing. The sub-class can pass its own _default_policy_.

```ruby
class UpdateUserForm < CreateUserForm
  # this will only run validations keys existing in the input
  schema(default_policy: :declared)
end
```

## A pattern: changing schema policy on the fly.

You can use a combination of `#clone` and `#policy` to change schema-wide field policies on the fly.

For example, you might have a form object that supports creating a new user and defining mandatory fields.

```ruby
class CreateUserForm
  include Paradocs::DSL

  schema do
    field(:name).present
    field(:age).present
  end

  attr_reader :errors, :params

  def initialize(payload: {})
    results = self.class.schema.resolve(payload)
    @errors = results.errors
    @params = results.output
  end

  def run!
    User.create(params)
  end
end
```

Now you might want to use the same form object to _update_ and existing user supporting partial updates.
In this case, however, attributes should only be validated if the attributes exist in the payload. We need to apply the `:declared` policy to all schema fields, only if a user exists.

We can do this by producing a clone of the class-level schema and applying any necessary policies on the fly.

```ruby
class CreateUserForm
  include Paradocs::DSL

  schema do
    field(:name).present
    field(:age).present
  end

  attr_reader :errors, :params

  def initialize(payload: {}, user: nil)
    @payload = payload
    @user = user

    # pick a policy based on user
    policy = user ? :declared : :noop
    # clone original schema and apply policy
    schema = self.class.schema.clone.policy(policy)

    # resolve params
    results = schema.resolve(params)
    @errors = results.errors
    @params = results.output
  end

  def run!
    if @user
      @user.update_attributes(params)
    else
      User.create(params)
    end
  end
end
```

## Multiple schema definitions

Form objects can optionally define more than one schema by giving them names:

```ruby
class UpdateUserForm
  include Paradocs::DSL

  # a schema named :query
  # for example for query parameters
  schema(:query) do
    field(:user_id).type(:integer).present
  end

  # a schema for PUT body parameters
  schema(:payload) do
    field(:name).present
    field(:age).present
  end
end
```

Named schemas are inherited and can be extended and given options in the same way as the nameless version.

Named schemas can be retrieved by name, ie. `UpdateUserForm.schema(:query)`.

If no name given, `.schema` uses `:schema` as default schema name.

## Expanding fields dynamically

Sometimes you don't know the exact field names but you want to allow arbitrary fields depending on a given pattern.

```ruby
# with this payload:
# {
#   title: "A title",
#   :"custom_attr_Color" => "red",
#   :"custom_attr_Material" => "leather"
# }

schema = Paradocs::Schema.new do
  field(:title).type(:string).present
  # here we allow any field starting with /^custom_attr/
  # this yields a MatchData object to the block
  # where you can define a Field and validations on the fly
  # https://ruby-doc.org/core-2.2.0/MatchData.html
  expand(/^custom_attr_(.+)/) do |match|
    field(match[1]).type(:string).present
  end
end

results = schema.resolve({
  title: "A title",
  :"custom_attr_Color" => "red",
  :"custom_attr_Material" => "leather",
  :"custom_attr_Weight" => "",
})

results.ouput[:Color] # => "red"
results.ouput[:Material] # => "leather"
results.errors["$.Weight"] # => ["is required and value must be present"]
```

NOTES: dynamically expanded field names are not included in `Schema#structure` metadata, and they are only processes if fields with the given expressions are present in the payload. This means that validations applied to those fields only run if keys are present in the first place.

## Structs

Structs turn schema definitions into objects graphs with attribute readers.

Add optional `Paradocs::Struct` module to define struct-like objects with schema definitions.

```ruby
require 'parametric/struct'

class User
  include Paradocs::Struct

  schema do
    field(:name).type(:string).present
    field(:friends).type(:array).schema do
      field(:name).type(:string).present
      field(:age).type(:integer)
    end
  end
end
```

`User` objects can be instantiated with hash data, which will be coerced and validated as per the schema definition.

```ruby
user = User.new(
  name: 'Joe',
  friends: [
    {name: 'Jane', age: 40},
    {name: 'John', age: 30},
  ]
)

# properties
user.name # => 'Joe'
user.friends.first.name # => 'Jane'
user.friends.last.age # => 30
```

### Errors

Both the top-level and nested instances contain error information:

```ruby
user = User.new(
  name: '', # invalid
  friends: [
    # friend name also invalid
    {name: '', age: 40},
  ]
)

user.valid? # false
user.errors['$.name'] # => "is required and must be present"
user.errors['$.friends[0].name'] # => "is required and must be present"

# also access error in nested instances directly
user.friends.first.valid? # false
user.friends.first.errors['$.name'] # "is required and must be valid"
```

### .new!(hash)

Instantiating structs with `.new!(hash)` will raise a `Paradocs::InvalidStructError` exception if the data is validations fail. It will return the struct instance otherwise.

`Paradocs::InvalidStructError` includes an `#errors` property to inspect the errors raised.

```ruby
begin
  user = User.new!(name: '')
rescue Paradocs::InvalidStructError => e
  e.errors['$.name'] # "is required and must be present"
end
```

### Nested structs

You can also pass separate struct classes in a nested schema definition.

```ruby
class Friend
  include Paradocs::Struct

  schema do
    field(:name).type(:string).present
    field(:age).type(:integer)
  end
end

class User
  include Paradocs::Struct

  schema do
    field(:name).type(:string).present
    # here we use the Friend class
    field(:friends).type(:array).schema Friend
  end
end
```

### Inheritance

Struct subclasses can add to inherited schemas, or override fields defined in the parent.

```ruby
class AdminUser < User
  # inherits User schema, and can add stuff to its own schema
  schema do
    field(:permissions).type(:array)
  end
end
```

### #to_h

`Struct#to_h` returns the ouput hash, with values coerced and any defaults populated.

```ruby
class User
  include Paradocs::Struct
  schema do
    field(:name).type(:string)
    field(:age).type(:integer).default(30)
  end
end

user = User.new(name: "Joe")
user.to_h # {name: "Joe", age: 30}
```

### Struct equality

`Paradocs::Struct` implements `#==()` to compare two structs Hash representation (same as `struct1.to_h.eql?(struct2.to_h)`.

Users can override `#==()` in their own classes to do whatever they need.
