$:.unshift('lib').uniq!
require 'perpetuity'
require 'test_classes'

describe Perpetuity do
  before(:all) do
    # Use MongoDB for now as its the only one supported.
    mongodb = Perpetuity::MongoDB.new db: 'perpetuity_gem_test'
    Perpetuity.configure { data_source mongodb }
  end

  before(:each) do
    ArticleMapper.delete_all
  end

  describe 'persistence' do
    it "persists an object" do
      article = Article.new 'I have a title'
      ArticleMapper.insert article
      ArticleMapper.count.should == 1
      ArticleMapper.first.title.should == 'I have a title'
    end

    it 'returns the id of the persisted object' do
      article = Article.new
      ArticleMapper.insert(article).should == article.id
    end

    it "gives an id to objects" do
      article = Article.new
      ArticleMapper.give_id_to article, 1

      article.id.should == 1
    end

    describe 'id injection' do
      let(:article) { Article.new }
      before do
        ArticleMapper.insert article
      end

      it 'assigns an id to the inserted object' do
        article.should respond_to :id
      end

      it "assigns an id using Mapper.first" do
        article.id.should == ArticleMapper.first.id
      end

      it 'assigns an id using Mapper.retrieve.first' do
        article.id.should == ArticleMapper.retrieve.first.id
      end

      it 'assigns an id using Mapper.all.first' do
        article.id.should == ArticleMapper.all.first.id
      end
    end

    it "allows mappers to set the id field" do
      BookMapper.delete_all
      book = Book.new(title='My Title')

      BookMapper.insert book
      BookMapper.first.id.should == 'my-title'
    end
  end

  describe "deletion" do
    it 'deletes an object' do
      2.times { ArticleMapper.insert Article.new }
      ArticleMapper.delete ArticleMapper.first
      ArticleMapper.count.should == 1
    end

    it 'deletes an object with a given id' do
      article_id = ArticleMapper.insert Article.new
      expect {
        ArticleMapper.delete article_id
      }.to change { ArticleMapper.count }.by -1
    end
    
    describe "#delete_all" do
      it "should delete all objects of a certain class" do
        ArticleMapper.insert Article.new
        ArticleMapper.delete_all
        ArticleMapper.count.should == 0
      end
    end
  end

  describe "retrieval" do
    it "gets all the objects of a class" do
      ArticleMapper.insert Article.new
      ArticleMapper.all.count.should == 1

      ArticleMapper.insert Article.new
      ArticleMapper.all.count.should == 2
    end
    
    it "has an ID when retrieved" do
      ArticleMapper.insert Article.new
      ArticleMapper.first.id.should_not be_nil
    end
    
    it "returns a Perpetuity::Retrieval object" do
      ArticleMapper.retrieve(id: 1).should be_an_instance_of Perpetuity::Retrieval
    end

    it "gets an item with a specific ID" do
      ArticleMapper.insert Article.new
      article = ArticleMapper.first
      retrieved = ArticleMapper.find(article.id)

      retrieved.id.should == article.id
      retrieved.title.should == article.title
      retrieved.body.should == article.body
    end

    it "gets an item by its attributes" do
      article = Article.new
      ArticleMapper.insert article
      retrieved = ArticleMapper.retrieve(title: article.title)

      retrieved.to_a.should have(1).item
      retrieved.first.title.should == article.title
    end
  end

  describe 'pagination' do
    it 'specifies the page we want' do
      ArticleMapper.retrieve.should respond_to :page
    end

    it 'specify the quantity per page' do
      ArticleMapper.retrieve.should respond_to :per_page
    end

    it 'returns an empty set when there is no data for that page' do
      data = ArticleMapper.retrieve.page(2)
      data.should be_empty
    end

    it 'specifies per-page quantity' do
      5.times { |i| ArticleMapper.insert Article.new i }
      data = ArticleMapper.retrieve.page(3).per_page(2)
      data.should have(1).item
    end
  end

  describe 'associations with other objects' do
    class Topic
      attr_accessor :title
      attr_accessor :creator
    end

    class TopicMapper < Perpetuity::Mapper
      attribute :title, String
      attribute :creator, User
    end

    let(:user) { User.new }
    let(:topic) { Topic.new }
    before do
      TopicMapper.delete_all
      UserMapper.delete_all

      user.name = 'Flump'
      topic.creator = user
      topic.title = 'Title'

      UserMapper.insert user
      TopicMapper.insert topic
    end

    it 'can reference other objects' do
      TopicMapper.first.creator.should == user.id
    end

    it 'can retrieve associated objects' do
      topic = TopicMapper.first

      TopicMapper.load_association! topic, :creator
      topic.creator.name.should == 'Flump'
    end
  end

  describe 'updating' do
    let(:article) { Article.new }
    before do
      ArticleMapper.insert article
    end

    it 'updates an object in the database' do
      ArticleMapper.update article, title: 'I has a new title!'
      ArticleMapper.first.title.should == 'I has a new title!'
    end
  end

  describe 'instantiation' do
    let!(:article) { Article.new(title = 'My Title') }
    let!(:mapper) { ArticleMapper.new(article) }
    it 'saves data that has changed since last loaded' do
      ArticleMapper.insert article
      article.title = 'My New Title'

      mapper.save

      ArticleMapper.first.title.should == 'My New Title'
    end

    it 'inserts objects into the DB when instantiated' do
      expect { mapper.insert }.to change { mapper.class.count }.by(1)
    end
  end

  describe 'validations' do
    class Car
      attr_accessor :make, :model, :seats
    end

    class CarMapper < Perpetuity::Mapper
      attribute :make, String
      attribute :model, String
      attribute :seats, Integer

      validate do
        present :make
      end
    end

    it 'raises an exception when inserting an invalid object' do
      car = Car.new
      expect { CarMapper.insert car }.to raise_error
    end

    it 'does not raise an exception when validations are met' do
      car = Car.new
      car.make = "Volkswagen"
      expect { CarMapper.insert car }.not_to raise_error
    end
  end

  # The Message class stores its data members differently internally than it receives them
  it 'uses accessor methods to read/write data' do
    MessageMapper.delete_all

    message = Message.new 'My Message!'
    MessageMapper.insert message
    saved_message = MessageMapper.first
    saved_message.instance_variable_get(:@text).should == 'My Message!'.reverse
    saved_message.text.should == 'My Message!'
  end
end