module BitteCI
  module Graph
    class Node
      getter name
      getter edges

      def initialize(@name : String)
        @edges = {} of Node => Float64
      end

      def add_edge(to_node : Node, weight : Float64)
        @edges[to_node] = weight
      end

      def remove_edge(to_node)
        @edges.delete(to_node)
      end

      def ==(other : Node)
        name == other.name
      end

      def !=(other : Node)
        name != other.name
      end
    end

    class Directed
      getter vertices = [] of Node

      def initialize
        @index = Float64::INFINITY
        @lowlink = Float64::INFINITY
      end

      def add_vertex(name : String) : Node
        Node.new(name).tap do |node|
          @vertices << node
        end
      end

      def add_edge(from_node : Node, to_node : Node, weight : Float64)
        from = @vertices.find { |i| i == from_node }
        to = @vertices.find { |i| i == to_node }

        if from && to
          from.add_edge(to_node, weight)
        else
          raise "Node not found"
        end
      end
    end

    class BFS
      def run(graph, source)
        vertex_set = [] of Node
        vertices = graph.vertices
        dist = {} of Node => Float64
        prev = {} of String => String | Nil
        size = vertices.size

        (0...size).each do |i|
          dist[vertices[i]] = Float64::INFINITY
          prev[vertices[i].name] = nil
          vertex_set << vertices[i]
        end

        dist[source] = 0.0
        prev[source.name] = source.name
        visited = Array(String).new
        queue = Array(Node).new
        queue.push(source)

        until queue.empty?
          vertex = queue.pop
          if vertex.nil?
            raise "No vertex available in Queue"
          else
            vertex.edges.keys.each do |neighbour|
              if prev[neighbour.name].nil?
                dist[neighbour] = dist[vertex] + 1
                prev[neighbour.name] = vertex.name
                queue.push(neighbour)
              end
            end
          end
          visited.push(vertex.name)
        end

        visited
      end
    end

    class Dijkstras
      def initialize(graph, source)
        vertex_set = [] of Node
        vertices = graph.vertices
        @dist = {} of Node => Float64
        @prev = {} of String => String | Nil
        i = 0
        size = vertices.size
        while i < size
          @dist[vertices[i]] = Float64::INFINITY
          @prev[vertices[i].name] = nil
          vertex_set << vertices[i]
          i = i + 1
        end
        @dist[source] = 0.0

        while !vertex_set.empty?
          u = vertex_set.min_by { |n| @dist.fetch(n, Float64::INFINITY) }
          vertex_set.delete(u)
          u.edges.keys.each do |neighbour|
            if u.edges[neighbour] < 0
              raise Exception.new("graph contains negative edge")
            else
              temp = @dist[u] + u.edges[neighbour]
              if temp < @dist[neighbour]
                @dist[neighbour] = temp
                @prev[neighbour.name] = u.name
              end
            end
          end
        end
      end

      def shortest_path(source, target)
        set = [] of String
        temp = @prev[target.name]

        until temp.nil?
          set.insert(0, temp)
          temp = @prev[temp]
        end

        if set.empty? || set[0] != source.name
          set << source.name if target == source
        else
          set << target.name
        end

        set
      end

      def shortest_paths(source)
        vertex_path = Array(Array(String)).new

        @dist.keys.each do |vertex|
          path = shortest_path(source, vertex)
          vertex_path << path
        end

        vertex_path
      end
    end
  end
end

# log = Log.for("runner")
# config = BitteCI::Runner::Config.new({
#   "ci_cue" => "midnight.cue",
# }, nil)
# input = File.read("pr_midnight_1189.json")
#
# BitteCI::Runner.run(log, config, input)
