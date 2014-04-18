# Dragonfly::S3DataStore

Amazon AWS S3 data store for use with the [Dragonfly](http://github.com/markevans/dragonfly) gem.

## Gemfile

```ruby
gem 'dragonfly-s3_data_store'
```

## Usage
Configuration (remember the require)

```ruby
require 'dragonfly/s3_data_store'

Dragonfly.app.configure do
  # ...

  datastore :s3,
    bucket_name: 'my-bucket',
    access_key_id: 'blahblahblah',
    secret_access_key: 'blublublublu'

  # ...
end
```

### Available configuration options

```ruby
:bucket_name
:access_key_id
:secret_access_key
:region               # default 'us-east-1', see Dragonfly::S3DataStore::REGIONS for options
:storage_headers      # defaults to {'x-amz-acl' => 'public-read'}, can be overridden per-write - see below
:url_scheme           # defaults to "http"
:url_host             # defaults to "<bucket-name>.s3.amazonaws.com", or "s3.amazonaws.com/<bucket-name>" if not a valid subdomain
:use_iam_profile      # boolean - if true, no need for access_key_id or secret_access_key
:root_path            # store all content under a subdirectory - uids will be relative to this - defaults to nil
:fog_storage_options  # hash for passing any extra options to Fog::Storage.new, e.g. {path_style: true}
```

### Per-storage options
```ruby
Dragonfly.app.store(some_file, path: 'some/path.txt', headers: {'x-amz-acl' => 'public-read-write'})
```

or

```ruby
class MyModel
  dragonfly_accessor :photo do
    storage_options do |attachment|
      {
        path: "some/path/#{some_instance_method}/#{rand(100)}",
        headers: {"x-amz-acl" => "public-read-write"}
      }
    end
  end
end
```

**BEWARE!!!!** you must make sure the path (which will become the uid for the content) is unique and changes each time the content
is changed, otherwise you could have caching problems, as the generated urls will be the same for the same uid.

### Serving directly from S3

You can get the S3 url using

```ruby
Dragonfly.app.remote_url_for('some/uid')
```

or

```ruby
my_model.attachment.remote_url
```

or with an expiring url:

```ruby
my_model.attachment.remote_url(expires: 3.days.from_now)
```

or with an https url:

```ruby
my_model.attachment.remote_url(scheme: 'https')   # also configurable for all urls with 'url_scheme'
```

or with a custom host:

```ruby
my_model.attachment.remote_url(host: 'custom.domain')   # also configurable for all urls with 'url_host'
```
