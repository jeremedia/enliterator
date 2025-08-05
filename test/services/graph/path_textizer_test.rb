# frozen_string_literal: true

require "test_helper"

module Graph
  class PathTextizerTest < ActiveSupport::TestCase
    setup do
      @textizer = PathTextizer.new
    end
    
    test "textizes simple two-node path" do
      path_data = {
        nodes: [
          { id: 1, label: "Idea", name: "Radical Inclusion" },
          { id: 2, label: "Manifest", name: "Welcome Tent" }
        ],
        edges: ["embodies"]
      }
      
      result = @textizer.textize_path(path_data)
      assert_equal "Idea(Radical Inclusion) → embodies → Manifest(Welcome Tent)", result
    end
    
    test "textizes multi-hop path" do
      path_data = {
        nodes: [
          { id: 1, label: "Idea", name: "Radical Inclusion" },
          { id: 2, label: "Manifest", name: "Welcome Tent" },
          { id: 3, label: "Experience", name: "First-timer story" }
        ],
        edges: ["embodies", "elicits"]
      }
      
      result = @textizer.textize_path(path_data)
      expected = "Idea(Radical Inclusion) → embodies → Manifest(Welcome Tent) → elicits → Experience(First-timer story)"
      assert_equal expected, result
    end
    
    test "narrates simple path" do
      path_data = {
        nodes: [
          { id: 1, label: "Idea", name: "Radical Inclusion" },
          { id: 2, label: "Manifest", name: "Welcome Tent" }
        ],
        edges: ["embodies"]
      }
      
      result = @textizer.narrate_path(path_data)
      assert_equal "the idea of 'Radical Inclusion' embodies the manifestation 'Welcome Tent'.", result
    end
    
    test "narrates complex path with multiple hops" do
      path_data = {
        nodes: [
          { id: 1, label: "Idea", name: "Radical Inclusion" },
          { id: 2, label: "Manifest", name: "Welcome Tent" },
          { id: 3, label: "Experience", name: "newcomer welcomed" },
          { id: 4, label: "Emanation", name: "community growth" }
        ],
        edges: ["embodies", "elicits", "inspires"]
      }
      
      result = @textizer.narrate_path(path_data)
      assert result.include?("Radical Inclusion")
      assert result.include?("embodies")
      assert result.include?("Welcome Tent")
      assert result.include?("elicits")
      assert result.include?("inspires")
    end
    
    test "handles nodes without names gracefully" do
      path_data = {
        nodes: [
          { id: 1, label: "Idea" },
          { id: 2, label: "Manifest", repr_text: "Some artifact" }
        ],
        edges: ["embodies"]
      }
      
      result = @textizer.textize_path(path_data)
      assert result.include?("Idea #1")
      assert result.include?("Some artifact")
    end
    
    test "formats verbs with display names" do
      path_data = {
        nodes: [
          { id: 1, label: "Manifest", name: "Camp" },
          { id: 2, label: "Experience", name: "Story" }
        ],
        edges: ["is_elicited_by"]
      }
      
      result = @textizer.textize_path(path_data)
      assert result.include?("is elicited by")
    end
    
    test "handles symmetric relationships" do
      path_data = {
        nodes: [
          { id: 1, label: "Spatial", name: "Camp A" },
          { id: 2, label: "Spatial", name: "Camp B" }
        ],
        edges: ["adjacent_to"]
      }
      
      result = @textizer.textize_path(path_data)
      assert result.include?("is adjacent to")
    end
  end
end