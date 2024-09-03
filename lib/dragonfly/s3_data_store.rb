require 'fog/aws'
require 'dragonfly'
require 'cgi'
require 'securerandom'

Dragonfly::App.register_datastore(:s3){ Dragonfly::S3DataStore }

module Dragonfly
  class S3DataStore

    # Exceptions
    class NotConfigured < RuntimeError; end

    SUBDOMAIN_PATTERN = /^[a-z0-9][a-z0-9.-]+[a-z0-9]$/

    def initialize(opts={})
      @bucket_name = opts[:bucket_name]
      @access_key_id = opts[:access_key_id]
      @secret_access_key = opts[:secret_access_key]
      @region = opts[:region]
      @storage_headers = opts[:storage_headers] || {'x-amz-acl' => 'public-read'}
      @url_scheme = opts[:url_scheme] || 'http'
      @url_host = opts[:url_host]
      @use_iam_profile = opts[:use_iam_profile]
      @root_path = opts[:root_path]
      @fog_storage_options = opts[:fog_storage_options] || {}
      @sync_clock = opts.fetch(:sync_clock, true)
    end

    attr_accessor :bucket_name, :access_key_id, :secret_access_key, :region, :storage_headers, :url_scheme, :url_host, :use_iam_profile, :root_path, :fog_storage_options, :sync_clock

    def write(content, opts={})
      ensure_configured
      ensure_bucket_initialized

      headers = {'Content-Type' => content.mime_type}
      headers.merge!(opts[:headers]) if opts[:headers]
      uid = opts[:path] || generate_uid(content.name || 'file')

      rescuing_socket_errors do
        content.file do |f|
          storage.put_object(bucket_name, full_path(uid), f, full_storage_headers(headers, content.meta))
        end
      end

      uid
    end

    def read(uid)
      ensure_configured
      response = rescuing_socket_errors{ storage.get_object(bucket_name, full_path(uid)) }
      [response.body, headers_to_meta(response.headers)]
    rescue Excon::Errors::NotFound => e
      nil
    end

    def destroy(uid)
      rescuing_socket_errors{ storage.delete_object(bucket_name, full_path(uid)) }
    rescue Excon::Errors::NotFound, Excon::Errors::Conflict => e
      Dragonfly.warn("#{self.class.name} destroy error: #{e}")
    end

    def url_for(uid, opts={})
      if expires = opts[:expires]
        storage.get_object_https_url(bucket_name, full_path(uid), expires, {:query => opts[:query]})
      else
        scheme = opts[:scheme] || url_scheme
        host   = opts[:host]   || url_host || (
          bucket_name =~ SUBDOMAIN_PATTERN ? "#{bucket_name}.s3.amazonaws.com" : "s3.amazonaws.com/#{bucket_name}"
        )
        "#{scheme}://#{host}/#{full_path(uid)}"
      end
    end

    def domain
      case region
      when 'us-east-1', nil
        's3.amazonaws.com'
      else
        "s3-#{region}.amazonaws.com"
      end
    end

    def storage
      @storage ||= begin
        storage = Fog::Storage.new(fog_storage_options.merge({
          :provider => 'AWS',
          :aws_access_key_id => access_key_id,
          :aws_secret_access_key => secret_access_key,
          :region => region,
          :use_iam_profile => use_iam_profile
        }).reject {|name, option| option.nil?})
        storage.sync_clock if sync_clock
        storage
      end
    end

    def bucket_exists?
      rescuing_socket_errors{ storage.get_bucket_location(bucket_name) }
      true
    rescue Excon::Errors::NotFound => e
      false
    end

    private

    def ensure_configured
      unless @configured
        if use_iam_profile
          raise NotConfigured, "You need to configure #{self.class.name} with bucket_name" if bucket_name.nil?
        else
          [:bucket_name, :access_key_id, :secret_access_key].each do |attr|
            raise NotConfigured, "You need to configure #{self.class.name} with #{attr}" if send(attr).nil?
          end
        end
        @configured = true
      end
    end

    def ensure_bucket_initialized
      unless @bucket_initialized
        rescuing_socket_errors{ storage.put_bucket(bucket_name, 'LocationConstraint' => region) } unless bucket_exists?
        @bucket_initialized = true
      end
    end

    def generate_uid(name)
      "#{Time.now.strftime '%Y/%m/%d/%H/%M/%S'}/#{SecureRandom.uuid}/#{name}"
    end

    def full_path(uid)
      File.join *[root_path, uid].compact
    end

    def full_storage_headers(headers, meta)
      storage_headers.merge(meta_to_headers(meta)).merge(headers)
    end

    def headers_to_meta(headers)
      json = headers['x-amz-meta-json']
      if json && !json.empty?
        unescape_meta_values(Serializer.json_decode(json))
      elsif marshal_data = headers['x-amz-meta-extra']
        Utils.stringify_keys(Serializer.marshal_b64_decode(marshal_data))
      end
    end

    def meta_to_headers(meta)
      meta = escape_meta_values(meta)
      {'x-amz-meta-json' => Serializer.json_encode(meta)}
    end

    def rescuing_socket_errors(&block)
      yield
    rescue Excon::Errors::SocketError => e
      storage.reload
      yield
    end

    def escape_meta_values(meta)
      meta.inject({}) {|hash, (key, value)|
        hash[key] = value.is_a?(String) ? CGI.escape(value) : value
        hash
      }
    end

    def unescape_meta_values(meta)
      meta.inject({}) {|hash, (key, value)|
        hash[key] = value.is_a?(String) ? CGI.unescape(value) : value
        hash
      }
    end

  end
end
