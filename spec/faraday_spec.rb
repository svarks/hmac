require 'spec_helper'

describe "faraday" do
  before(:all) { Bundler.require(:faraday) }
  let!(:key_id)     { (0...8).map{ 65.+(rand(26)).chr}.join }
  let!(:key_secret) { (0...16).map{ 65.+(rand(26)).chr}.join }

  describe "adapter" do
    let!(:adapter)    { Ey::Hmac::Adapter::Faraday }

    it "should sign and read request" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = "{1: 2}"
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      expect(request[:request_headers]['Authorization']).to start_with("EyHmac")
      expect(request[:request_headers]['Content-Digest']).to eq(Digest::MD5.hexdigest(request[:body]))
      expect(Time.parse(request[:request_headers]['Date'])).not_to be_nil

      yielded = false

      expect(Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        expect(key_id).to eq(key_id)
        yielded = true
        key_secret
      end).to be_truthy

      expect(yielded).to be_truthy
    end

    it "should not set Content-Digest if body is nil" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = nil
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      expect(request[:request_headers]['Authorization']).to start_with("EyHmac")
      expect(request[:request_headers]).not_to have_key('Content-Digest')
      expect(Time.parse(request[:request_headers]['Date'])).not_to be_nil

      yielded = false

      expect(Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        expect(key_id).to eq(key_id)
        yielded = true
        key_secret
      end).to be_truthy

      expect(yielded).to be_truthy
    end

    it "should not set Content-Digest if body is empty" do
      request = Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = ""
        r.headers = {"Content-Type" => "application/xml"}
        end.to_env(Faraday::Connection.new("http://localhost"))

      Ey::Hmac.sign!(request, key_id, key_secret, adapter: adapter)

      expect(request[:request_headers]['Authorization']).to start_with("EyHmac")
      expect(request[:request_headers]).not_to have_key('Content-Digest')
      expect(Time.parse(request[:request_headers]['Date'])).not_to be_nil

      yielded = false

      expect(Ey::Hmac.authenticated?(request, adapter: adapter) do |key_id|
        expect(key_id).to eq(key_id)
        yielded = true
        key_secret
      end).to be_truthy

      expect(yielded).to be_truthy
    end

    context "with a request" do
    let!(:request) do
      Faraday::Request.new.tap do |r|
        r.method = :get
        r.path = "/auth"
        r.body = "{1: 2}"
        r.headers = {"Content-Type" => "application/xml"}
      end.to_env(Faraday::Connection.new("http://localhost"))
    end
      include_examples "authentication"
    end
  end

  describe "middleware" do
    it "should accept a SHA1 signature" do
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, accept_digests: :sha1, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      connection = Faraday.new do |c|
        c.use :hmac, key_id, key_secret, sign_with: :sha1
        c.adapter(:rack, app)
      end

      expect(connection.get("/resources").status).to eq(200)
    end

    it "should accept a SHA256 signature" do # default
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      connection = Faraday.new do |c|
        c.use :hmac, key_id, key_secret
        c.adapter(:rack, app)
      end

      expect(connection.get("/resources").status).to eq(200)
    end

    it "should accept multiple digest signatures" do # default
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      app = lambda do |env|
        authenticated = Ey::Hmac.authenticated?(env, accept_digests: [:sha1, :sha256], adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
          (auth_id == key_id) && key_secret
        end
        [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
      end

      connection = Faraday.new do |c|
        c.use :hmac, key_id, key_secret
        c.adapter(:rack, app)
      end

      expect(connection.get("/resources").status).to eq(200)
    end

    it "should sign empty request" do
      require 'ey-hmac/faraday'
      Bundler.require(:rack)

      _key_id, _key_secret = key_id, key_secret
      app = Rack::Builder.new do
        use Rack::Config do |env|
          env["CONTENT_TYPE"] ||= "text/html"
        end
        run(lambda {|env|
          authenticated = Ey::Hmac.authenticate!(env, adapter: Ey::Hmac::Adapter::Rack) do |auth_id|
            (auth_id == _key_id) && _key_secret
          end
          [(authenticated ? 200 : 401), {"Content-Type" => "text/plain"}, []]
        })
      end

      connection = Faraday.new do |c|
        c.use :hmac, key_id, key_secret
        c.adapter(:rack, app)
      end

      expect(connection.get do |req|
        req.path  = "/resource"
        req.body = nil
        req.params = {"a" => "1"}
        req.headers = {"Content-Type" => "application/x-www-form-urlencoded"}
      end.status).to eq(200)
    end
  end
end
