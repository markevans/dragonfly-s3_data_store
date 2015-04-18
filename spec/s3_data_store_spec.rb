require 'spec_helper'
require 'dragonfly/spec/data_store_examples'
require 'yaml'
require 'dragonfly/s3_data_store'

describe Dragonfly::S3DataStore do

  # To run these tests, put a file ".s3_spec.yml" in the dragonfly root dir, like this:
  # key: XXXXXXXXXX
  # secret: XXXXXXXXXX
  # enabled: true
  if File.exist?(file = File.expand_path('../../.s3_spec.yml', __FILE__))
    config = YAML.load_file(file)
    KEY = config['key']
    SECRET = config['secret']
    enabled = config['enabled']
  else
    enabled = false
  end

  if enabled

    # Make sure it's a new bucket name
    BUCKET_NAME = "dragonfly-test-#{Time.now.to_i.to_s(36)}"

    before(:each) do
      @data_store = Dragonfly::S3DataStore.new(
        :bucket_name => BUCKET_NAME,
        :access_key_id => KEY,
        :secret_access_key => SECRET,
        :region => 'eu-west-1'
      )
    end

  else

    BUCKET_NAME = 'test-bucket'

    before(:each) do
      Fog.mock!
      @data_store = Dragonfly::S3DataStore.new(
        :bucket_name => BUCKET_NAME,
        :access_key_id => 'XXXXXXXXX',
        :secret_access_key => 'XXXXXXXXX',
        :region => 'eu-west-1'
      )
    end

  end

  it_should_behave_like 'data_store'

  let (:app) { Dragonfly.app }
  let (:content) { Dragonfly::Content.new(app, "eggheads") }
  let (:new_content) { Dragonfly::Content.new(app) }

  describe "registering with a symbol" do
    it "registers a symbol for configuring" do
      app.configure do
        datastore :s3
      end
      app.datastore.should be_a(Dragonfly::S3DataStore)
    end
  end

  describe "write" do
    it "should use the name from the content if set" do
      content.name = 'doobie.doo'
      uid = @data_store.write(content)
      uid.should =~ /doobie\.doo$/
      new_content.update(*@data_store.read(uid))
      new_content.data.should == 'eggheads'
    end

    it "should work ok with files with funny names" do
      content.name = "A Picture with many spaces in its name (at 20:00 pm).png"
      uid = @data_store.write(content)
      uid.should =~ /A Picture with many spaces in its name \(at 20:00 pm\)\.png/
      new_content.update(*@data_store.read(uid))
      new_content.data.should == 'eggheads'
    end

    it "should allow for setting the path manually" do
      uid = @data_store.write(content, :path => 'hello/there')
      uid.should == 'hello/there'
      new_content.update(*@data_store.read(uid))
      new_content.data.should == 'eggheads'
    end

    if enabled # Fog.mock! doesn't act consistently here
      it "should reset the connection and try again if Fog throws a socket EOFError" do
        @data_store.storage.should_receive(:put_object).exactly(:once).and_raise(Excon::Errors::SocketError.new(EOFError.new))
        @data_store.storage.should_receive(:put_object).with(BUCKET_NAME, anything, anything, hash_including)
        @data_store.write(content)
      end

      it "should just let it raise if Fog throws a socket EOFError again" do
        @data_store.storage.should_receive(:put_object).and_raise(Excon::Errors::SocketError.new(EOFError.new))
        @data_store.storage.should_receive(:put_object).and_raise(Excon::Errors::SocketError.new(EOFError.new))
        expect{
          @data_store.write(content)
        }.to raise_error(Excon::Errors::SocketError)
      end
    end
  end

  describe "domain" do
    it "should default to the US" do
      @data_store.region = nil
      @data_store.domain.should == 's3.amazonaws.com'
    end

    it "should return the correct domain" do
      @data_store.region = 'eu-west-1'
      @data_store.domain.should == 's3-eu-west-1.amazonaws.com'
    end

    it "does raise an error if an unknown region is given" do
      @data_store.region = 'latvia-central'
      lambda{
        @data_store.domain
      }.should raise_error
    end
  end

  describe "not configuring stuff properly" do
    it "should require a bucket name on write" do
      @data_store.bucket_name = nil
      proc{ @data_store.write(content) }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    it "should require an access_key_id on write" do
      @data_store.access_key_id = nil
      proc{ @data_store.write(content) }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    it "should require a secret access key on write" do
      @data_store.secret_access_key = nil
      proc{ @data_store.write(content) }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    it "should require a bucket name on read" do
      @data_store.bucket_name = nil
      proc{ @data_store.read('asdf') }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    it "should require an access_key_id on read" do
      @data_store.access_key_id = nil
      proc{ @data_store.read('asdf') }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    it "should require a secret access key on read" do
      @data_store.secret_access_key = nil
      proc{ @data_store.read('asdf') }.should raise_error(Dragonfly::S3DataStore::NotConfigured)
    end

    if !enabled #this will fail since the specs are not running on an ec2 instance with an iam role defined
      it 'should allow missing secret key and access key on write if iam profiles are allowed' do
        # This is slightly brittle but it's annoying waiting for fog doing stuff
        @data_store.storage.stub(:get_bucket_location => nil, :put_object => nil)

        @data_store.use_iam_profile = true
        @data_store.secret_access_key = nil
        @data_store.access_key_id = nil
        expect{ @data_store.write(content) }.not_to raise_error
      end
    end
  end

  describe "root_path" do
    before do
      content.name = "something.png"
      @data_store.root_path = "some/path"
    end

    it "stores files in the provided sub directory" do
      @data_store.storage.should_receive(:put_object).with(BUCKET_NAME, /^some\/path\/.*\/something\.png$/, anything, anything)
      @data_store.write(content)
    end

    it "finds files in the provided sub directory" do
      mock_response = double("response", body: "", headers: {})
      uid = @data_store.write(content)
      @data_store.storage.should_receive(:get_object).with(BUCKET_NAME, /^some\/path\/.*\/something\.png$/).and_return(mock_response)
      @data_store.read(uid)
    end

    it "does not alter the uid" do
      uid = @data_store.write(content)
      uid.should include("something.png")
      uid.should_not include("some/path")
    end

    it "destroys files in the provided sub directory" do
      uid = @data_store.write(content)
      @data_store.storage.should_receive(:delete_object).with(BUCKET_NAME, /^some\/path\/.*\/something\.png$/)
      @data_store.destroy(uid)
    end

    describe "url_for" do
      before do
        @uid = @data_store.write(content)
      end

      it "returns the uid prefixed with the root_path" do
        @data_store.url_for(@uid).should =~ /some\/path\/.*\/something\.png/
      end

      it "gives an expiring url" do
        @data_store.url_for(@uid, :expires => 1301476942).should =~ /\/some\/path\/.*\/something\.png\?X-Amz-Expires=/
      end
    end
  end

  describe "autocreating the bucket" do
    it "should create the bucket on write if it doesn't exist" do
      @data_store.bucket_name = "dragonfly-test-blah-blah-#{rand(100000000)}"
      @data_store.write(content)
    end

    it "should not try to create the bucket on read if it doesn't exist" do
      @data_store.bucket_name = "dragonfly-test-blah-blah-#{rand(100000000)}"
      @data_store.send(:storage).should_not_receive(:put_bucket)
      @data_store.read("gungle").should be_nil
    end
  end

  describe "headers" do
    before(:each) do
      @data_store.storage_headers = {'x-amz-foo' => 'biscuithead'}
    end

    it "should allow configuring globally" do
      @data_store.storage.should_receive(:put_object).with(BUCKET_NAME, anything, anything,
        hash_including('x-amz-foo' => 'biscuithead')
      )
      @data_store.write(content)
    end

    it "should allow adding per-store" do
      @data_store.storage.should_receive(:put_object).with(BUCKET_NAME, anything, anything,
        hash_including('x-amz-foo' => 'biscuithead', 'hello' => 'there')
      )
      @data_store.write(content, :headers => {'hello' => 'there'})
    end

    it "should let the per-store one take precedence" do
      @data_store.storage.should_receive(:put_object).with(BUCKET_NAME, anything, anything,
        hash_including('x-amz-foo' => 'override!')
      )
      @data_store.write(content, :headers => {'x-amz-foo' => 'override!'})
    end

    it "should write setting the content type" do
      @data_store.storage.should_receive(:put_object) do |_, __, ___, headers|
        headers['Content-Type'].should == 'image/png'
      end
      content.name = 'egg.png'
      @data_store.write(content)
    end

    it "allow overriding the content type" do
      @data_store.storage.should_receive(:put_object) do |_, __, ___, headers|
        headers['Content-Type'].should == 'text/plain'
      end
      content.name = 'egg.png'
      @data_store.write(content, :headers => {'Content-Type' => 'text/plain'})
    end
  end

  describe "urls for serving directly" do

    before(:each) do
      @uid = 'some/path/on/s3'
    end

    it "should use the bucket subdomain" do
      @data_store.url_for(@uid).should == "http://#{BUCKET_NAME}.s3.amazonaws.com/some/path/on/s3"
    end

    it "should use path style if the bucket is not a valid S3 subdomain" do
      bucket_name = BUCKET_NAME.upcase
      @data_store.bucket_name = bucket_name
      @data_store.url_for(@uid).should == "http://s3.amazonaws.com/#{bucket_name}/some/path/on/s3"
    end

    it "should use the bucket subdomain for other regions too" do
      @data_store.region = 'eu-west-1'
      @data_store.url_for(@uid).should == "http://#{BUCKET_NAME}.s3.amazonaws.com/some/path/on/s3"
    end

    it "should give an expiring url" do
      @data_store.url_for(@uid, :expires => 1301476942).should =~
        %r{^https://#{BUCKET_NAME}\.#{@data_store.domain}/some/path/on/s3\?X-Amz-Expires=}
    end

    it "should allow for using https" do
      @data_store.url_for(@uid, :scheme => 'https').should == "https://#{BUCKET_NAME}.s3.amazonaws.com/some/path/on/s3"
    end

    it "should allow for always using https" do
      @data_store.url_scheme = 'https'
      @data_store.url_for(@uid).should == "https://#{BUCKET_NAME}.s3.amazonaws.com/some/path/on/s3"
    end

    it "should allow for customizing the host" do
      @data_store.url_for(@uid, :host => 'customised.domain.com/and/path').should == "http://customised.domain.com/and/path/some/path/on/s3"
    end

    it "should allow the url_host to be customised permanently" do
      url_host = 'customised.domain.com/and/path'
      @data_store.url_host = url_host
      @data_store.url_for(@uid).should == "http://#{url_host}/some/path/on/s3"
    end

  end

  describe "meta" do
    it "uses the x-amz-meta-json header for meta" do
      uid = @data_store.write(content, :headers => {'x-amz-meta-json' => Dragonfly::Serializer.json_encode({'potato' => 44})})
      c, meta = @data_store.read(uid)
      meta['potato'].should == 44
    end

    it "works with the deprecated x-amz-meta-extra header (but stringifies its keys)" do
      uid = @data_store.write(content, :headers => {
        'x-amz-meta-extra' => Dragonfly::Serializer.marshal_b64_encode(:some => 'meta', :wo => 4),
        'x-amz-meta-json' => ""
      })
      c, meta = @data_store.read(uid)
      meta['some'].should == 'meta'
      meta['wo'].should == 4
    end

    it "works with non ascii character" do
      content = Dragonfly::Content.new(app, "hi", "name" => "こんにちは.txt")
      uid = @data_store.write(content)
      c, meta = @data_store.read(uid)
      meta['name'].should == 'こんにちは.txt'
    end
  end

  describe "fog_storage_options" do
    it "adds options to Fog::Storage object" do
      @data_store.fog_storage_options = {:random_option => 'look at me!'}
      Fog::Storage.should_receive(:new).with do |hash|
        hash[:random_option].should == 'look at me!'
        hash[:aws_access_key_id].should match /\w+/
      end.and_call_original
      @data_store.storage
    end
  end
end
