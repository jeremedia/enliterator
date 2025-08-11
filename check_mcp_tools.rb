#!/usr/bin/env ruby
# Check MCP tools configuration

puts "=== MCP TOOLS ANALYSIS ==="

arctic_ekn = Ekn.find_by!(slug: "arctic-research")
personality = arctic_ekn.ekn_personality_profile

puts "Personality MCP Tool Preferences:"
personality.mcp_tool_preferences.each do |tool, preference|
  puts "  #{tool}: #{preference}"
end

puts "\nTotal MCP Tools Configured: #{personality.mcp_tool_preferences.keys.count}"

puts "\nExpected MCP Tools (from MCP server spec):"
expected_tools = [
  "search", 
  "fetch", 
  "bridge", 
  "extract_and_link", 
  "analyze_pools",
  "location_neighbors",
  "set_persona",
  "clear_persona", 
  "explain_path",
  "rights_check"
]

expected_tools.each do |tool|
  configured = personality.mcp_tool_preferences.key?(tool)
  puts "  #{tool}: #{configured ? '✅ Configured' : '❌ Missing'}"
end

puts "\nShould update personality profile to include all #{expected_tools.count} tools!"