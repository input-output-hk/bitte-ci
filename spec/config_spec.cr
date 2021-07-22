require "spec"
require "../src/bitte_ci/simple_config"

struct Config
  include SimpleConfig::Configuration

  property sub : Sub?

  @[Option(short: 'a', long: "aa", env: "A", help: "a")]
  property a : String

  @[Option(short: 'd', env: "D", help: "d")]
  property d : String = "from default"
end

struct Sub
  include SimpleConfig::Configuration

  @[Option(short: 's', env: "S", help: "s")]
  property s : String
end

struct Types
  include SimpleConfig::Configuration

  @[Option(help: "uri")]
  property url : URI

  @[Option(help: "arr")]
  property arr : Array(String)
end

Spec.before_each do
  ENV.delete "A"
end

describe SimpleConfig::Configuration do
  empty = {} of String => String
  file = File.join(__DIR__, "fixtures/tiny.json.fixture")

  it "is configurable from environment" do
    ENV["A"] = "from env"
    c = Config.new(empty, file: nil)
    c.a.should eq("from env")
  end

  it "is configurable from a hash" do
    c = Config.new({"a" => "from flag"}, file: nil)
    c.a.should eq("from flag")
  end

  it "is configurable from a file" do
    c = Config.new(empty, file: file)
    c.a.should eq("from file")
  end

  it "is configurable from default" do
    c = Config.new(empty, file: file)
    c.d.should eq("from default")
  end

  it "prefers file over env" do
    ENV["A"] = "from env"
    c = Config.new(empty, file: file)
    c.a.should eq("from file")
  end

  it "prefers flag over file" do
    ENV["A"] = "from env"
    c = Config.new({"a" => "from flag"}, file: file)
    c.a.should eq("from flag")
  end

  it "is configurable on the fly" do
    main_config = {} of String => String
    sub_config = {} of String => String

    op = OptionParser.new do |parser|
      Config.option_parser(parser, main_config)

      parser.on "sub", "first subcommand" do
        Sub.option_parser(parser, sub_config)
      end
    end

    op.parse(["sub", "-s", "from flag s", "--aa", "from flag a", "-d", "from flag d"])

    Sub.new(sub_config, nil).s.should eq("from flag s")

    Config.new(main_config, nil).a.should eq("from flag a")
    Config.new(main_config, nil).d.should eq("from flag d")
  end

  it "handles different urls and json arrays" do
    c = Types.new({
      "url" => "http://example.com",
      "arr" => %(["a", "b"]),
    }, nil)
    c.url.should eq(URI.parse("http://example.com"))
    c.arr.should eq(["a", "b"])
  end

  it "handles different comma separated arrays" do
    c = Types.new({
      "url" => "http://example.com",
      "arr" => "a,b",
    }, nil)
    c.url.should eq(URI.parse("http://example.com"))
    c.arr.should eq(["a", "b"])
  end

  it "complains about a missing option" do
    error = SimpleConfig::Error.missing_flag("url", nil, nil, nil)
    expect_raises(error.class, error.message) {
      Types.new({} of String => String, nil).url
    }
  end

  it "complains about a missing file option" do
    error = SimpleConfig::Error.missing_flag("url", nil, nil, nil)
    expect_raises(error.class, error.message) {
      Types.new({} of String => String, nil)
    }
  end

  it "complains about a missing fully specified option" do
    error = SimpleConfig::Error.missing_flag("a", 'a', "aa", "A")
    expect_raises(error.class, error.message) {
      Config.new({} of String => String, nil)
    }
  end
end
