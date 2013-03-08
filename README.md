# Perpetuity [![Build Status](https://secure.travis-ci.org/jgaskins/perpetuity.png)](http://travis-ci.org/jgaskins/perpetuity) [![Code Climate](https://codeclimate.com/github/jgaskins/perpetuity.png)](https://codeclimate.com/github/jgaskins/perpetuity)

Perpetuity is a simple Ruby object persistence layer that attempts to follow Martin Fowler's Data Mapper pattern, allowing you to use plain-old Ruby objects in your Ruby apps in order to decouple your domain logic from the database as well as speed up your tests. There is no need for your model classes to inherit from another class or even include a mix-in.

Your objects will hopefully eventually be able to be persisted into whichever database you like. Right now, only MongoDB is supported. Other persistence solutions will come later.

This gem was inspired by [a blog post by Steve Klabnik](http://blog.steveklabnik.com/posts/2011-12-30-active-record-considered-harmful).

## How it works

In the Data Mapper pattern, the objects you work with don't understand how to persist themselves. They interact with other objects just as in any other object-oriented application, leaving all persistence logic to mapper objects. This decouples them from the database and allows you to write your code without it in mind.

## Installation

Add the following to your Gemfile and run `bundle` to install it.

```ruby
gem 'perpetuity'
```

## Configuration

The only currently supported persistence method is MongoDB. Other schemaless solutions can probably be implemented easily.

```ruby
mongodb = Perpetuity::MongoDB.new(
  db: 'example_db',            # Required
  host: 'mongodb.example.com', # Default: 'localhost'
  port: 27017,                 # Default: 27017
  username: 'mongo',           # If no username/password given, do not authenticate
  password: 'password'
)

Perpetuity.configure do 
  data_source mongodb
end
```

## Setting up object mappers

Object mappers are generated by the following:

```ruby
Perpetuity.generate_mapper_for MyClass do
  attribute :my_attribute
  attribute :my_other_attribute

  index :my_attribute
end
```

The primary mapper configuration will be configuring attributes to be persisted. This is done using the `attribute` method. Calling `attribute` will add the specified attribute and its class to the mapper's attribute set. This is how the mapper knows what to store and how to store it. Here is an example of an `Article` class, its mapper and how it can be saved to the database.

Accessing mappers after they've been generated is done through the use of the subscript operator on the `Perpetuity` module. For example, if you generate a mapper for an `Article` class, you can access it by calling `Perpetuity[Article]`.

```ruby
class Article
  attr_accessor :title, :body
end

Perpetuity.generate_mapper_for Article do
  attribute :title
  attribute :body
end

article = Article.new
article.title = 'New Article'
article.body = 'This is an article.'

Perpetuity[Article].insert article
```

## Loading Objects

You can load all persisted objects of a particular class by sending `all` to the mapper object. Example:

```ruby
Perpetuity[Article].all
```

You can load specific objects by calling the `find` method with an ID param on the mapper and passing in the criteria. You may also specify more general criteria using the `select` method with a block similar to `Enumerable#select`.

```ruby
article  = Perpetuity[Article].find params[:id]
users    = Perpetuity[User].select { |user| user.email == 'me@example.com' }
articles = Perpetuity[Article].select { |article| article.published_at < Time.now }
comments = Perpetuity[Comment].select { |comment| comment.article_id.in articles.map(&:id) }
```

These methods will return a Perpetuity::Retrieval object, which will lazily retrieve the objects from the database. They will wait to hit the DB when you begin iterating over the objects so you can continue chaining methods, similar to ActiveRecord.

```ruby
article_mapper = Perpetuity[Article]
articles = article_mapper.select { |article| article.published_at < Time.now }
                         .sort(:published_at)
                         .reverse
                         .page(2)
                         .per_page(10) # built-in pagination

articles.each do |article| # This is when the DB gets hit
  # Display the pretty articles
end
```

Unfortunately, due to limitations in the Ruby language itself, we cannot get a true `Enumerable`-style select method. The limitation shows itself when needing to have multiple criteria for a query, as in this super-secure example:

```ruby
user = Perpetuity[User].select { |user| (user.email == params[:email]) & (user.password == params[:password]) }
```

Notice that we have to use a single `&` and surround each criterion with parentheses. If we could override `&&` and `||`, we could put more Rubyesque code in here, but until then, we have to operate within the boundaries of the operators that can be overridden.

## Associations with Other Objects

The database can natively serialize some objects. For example, MongoDB can serialize `String`, `Numeric`, `Array`, `Hash`, `Time`, `nil`, `true`, `false`, and a few others. For other data types, you must determine whether you want those attributes embedded within the same document in the database or attached as a reference. For example, a `Post` could have `Comment`s, which would likely be embedded within the post object. But these comments could have an `author` attribute that references the `Person` that wrote the comment. Embedding the author in this case is not a good idea since it would be a duplicate of the `Person` that wrote it, which would then be out of sync if the original object is modified.

If an object references another type of object, the association is declared just as any other attribute. No special treatment is required. For embedded relationships, make sure you use the `embedded: true` option in the attribute.

```ruby
Perpetuity.generate_mapper_for Article do
  attribute :title
  attribute :body
  attribute :author
  attribute :comments, embedded: true
  attribute :timestamp
end

Perpetuity.generate_mapper_for Comment do
  attribute :body
  attribute :author
  attribute :timestamp
end
```

In this case, the article has an array of `Comment` objects, which the serializer knows that MongoDB cannot serialize. It will then tell the `Comment` mapper to serialize it and it stores that within the array.

If some of the comments aren't objects of class `Comment`, it will adapt and serialize them according to their class. This works very well for objects that can have attributes of various types, such as a `User` having a profile attribute that can be either a `UserProfile` or `AdminProfile` object. You don't need to declare anything different for this case, just store the appropriate type of object into the `User`'s `profile` attribute and the mapper will take care of the details.

If the associated object's class has a mapper defined, it will be used by the parent object's mapper for serialization. Otherwise, the object will be `Marshal.dump`ed. If the object cannot be marshaled, the object cannot be serialized and an exception will be raised.

When you load an object that has embedded associations, the embedded attributes are loaded immediately. For referenced associations, though, only the object itself will be loaded. All referenced objects must be loaded with the `load_association!` mapper call.

```ruby
user_mapper = Perpetuity[User]
user = user_mapper.find(params[:id])
user_mapper.load_association! user, :profile
```

This loads up the user's profile and injects it into the profile attribute. All loading of referenced objects is explicit so that we don't load an entire object graph unnecessarily. This encourages (forces, really) you to think about all of the objects you'll be loading.

If you want to load a 1:N, N:1 or M:N association, Perpetuity handles that for you.

```ruby
article_mapper = Perpetuity[Article]
articles = article_mapper.all.to_a
article_mapper.load_association! articles.first, :tags # 1:N
article_mapper.load_association! articles, :author     # All author objects for these articles load in a single query - N:1
article_mapper.load_association! articles, :tags       # M:N
```

## Customizing persistence

Setting the ID of a record to a custom value rather than using the DB default.

```ruby
Perpetuity.generate_mapper_for Article do
  id { title.gsub(/\W+/, '-') } # use the article's parameterized title attribute as its ID
end
```

The block passed to the `id` macro is evaluated in the context of the object being persisted. This allows you to use the object's private methods and instance variables if you need to.

## Indexing

Indexes are declared with the `index` method. The simplest way to create an index is just to pass the attribute to be indexed as a parameter:

```ruby
Perpetuity.generate_mapper_for Article do
  index :title
end
```

The following will generate a unique index on an `Article` class so that two articles cannot be added to the database with the same title. This eliminates the need for uniqueness validations (like ActiveRecord has) that check for existence of that value. Uniqueness validations have race conditions and don't protect you at the database level. Using unique indexes is a superior way to do this.

```ruby
Perpetuity.generate_mapper_for Article do
  index :title, unique: true
end
```

Also, MongoDB, as well as some other databases, provide the ability to specify an order for the index. For example, if you want to query your blog with articles in descending order, you can specify a descending-order index on the timestamp for increased query performance.

```ruby
Perpetuity.generate_mapper_for Article do
  index :timestamp, order: :descending
end
```

### Applying indexes

It's very important to keep in mind that specifying an index does not create it on the database immediately. If you did this, you could potentially introduce downtime every time you specify a new index and deploy your application.

In order to apply indexes to the database, you must send `reindex!` to the mapper. For example:

```ruby
class ArticleMapper < Perpetuity::Mapper
  map Article
  attribute :title
  index :title, unique: true
end

Perpetuity[Article].reindex!
```

## Contributing

Right now, this code is pretty bare and there are possibly some design decisions that need some more refinement. You can help. If you have ideas to build on this, send some love in the form of pull requests or issues or [tweets](http://twitter.com/jamie_gaskins) or e-mails and I'll do what I can for them.
