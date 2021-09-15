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

      def send_status(user : String, token : String, state : String, target_url : URI, description : String, context = "Bitte CI")
        body = {
          state:       state,
          target_url:  target_url,
          description: description[0..138],
          context:     context,
        }

        Log.info &.emit(
          "sending github status",
          state: body[:state],
          target_url: body[:target_url].to_s,
          description: body[:description],
          context: body[:context],
        )

        uri = URI.parse(statuses_url)
        client = HTTP::Client.new(uri)
        client.basic_auth user, token
        res = client.post(
          uri.path,
          headers: HTTP::Headers{
            "Accept" => "application/vnd.github.v3+json",
          },
          body: body.to_json,
        )

        case res.status
        when HTTP::Status::CREATED
          res
        else
          Log.error {
            "HTTP Error while trying to POST github status to #{uri} : #{res.status.to_i} #{res.status_message}"
          }
        end
      rescue e : Socket::ConnectError
        Log.error &.emit(e.inspect, url: statuses_url.to_s)
      end
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
