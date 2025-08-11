#!/usr/bin/env ruby
# Update Arctic Research Navigator with all 10 MCP tools

arctic_ekn = Ekn.find_by!(slug: "arctic-research")
personality = arctic_ekn.ekn_personality_profile

# Update MCP tool preferences to include all 10 tools
updated_preferences = {
  "search" => 0.9,           # Primary tool for knowledge discovery
  "fetch" => 0.8,            # Deep document analysis  
  "bridge" => 0.7,           # Connection discovery between concepts
  "extract_and_link" => 0.6, # Entity extraction from user queries
  "analyze_pools" => 0.7,    # Analyze text for pool distribution
  "location_neighbors" => 0.5, # Spatial analysis (less relevant for Arctic docs but available)
  "explain_path" => 0.6,     # Explain reasoning paths
  "rights_check" => 0.8,     # Verify usage rights for content
  "set_persona" => 0.3,      # Lower priority - personality management
  "clear_persona" => 0.2     # Lower priority - reset personality state
}

personality.update!(mcp_tool_preferences: updated_preferences)

puts "✅ Updated Arctic Research Navigator MCP Tools"
puts "Total tools: #{personality.mcp_tool_preferences.keys.count}"
puts "\nTool preferences (sorted by priority):"
personality.mcp_tool_preferences.sort_by { |k,v| -v }.each do |tool, pref|
  priority = pref >= 0.7 ? "(high)" : pref >= 0.5 ? "(medium)" : "(low)"
  puts "  #{tool}: #{pref} #{priority}"
end

puts "\n🎯 Arctic Research Navigator now has access to all #{personality.mcp_tool_preferences.keys.count} MCP tools!"