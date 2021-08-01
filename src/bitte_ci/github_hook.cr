require "json"

module BitteCI
  class GithubHook
    include JSON::Serializable

    property pull_request : PullRequest

    class PullRequest
      include JSON::Serializable

      property id : UInt64
      property number : UInt64
      property base : Base
      property head : Base
      property statuses_url : String
    end

    class Base
      include JSON::Serializable

      property repo : Repo
      property sha : String
      property label : String
      property ref : String
    end

    class Repo
      include JSON::Serializable

      property full_name : String
      property clone_url : String
    end
  end
end
