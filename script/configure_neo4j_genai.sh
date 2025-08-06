#!/bin/bash
# Configure Neo4j for GenAI/GDS procedures

NEO4J_CONF="/Users/jeremy/Library/Application Support/neo4j-desktop/Application/Data/dbmss/dbms-3f4feab6-6708-46d6-ad3d-95c49ec730e5/conf/neo4j.conf"

echo "📝 Updating Neo4j configuration for GenAI/GDS..."

# Check if config file exists
if [ ! -f "$NEO4J_CONF" ]; then
    echo "❌ Neo4j config not found at: $NEO4J_CONF"
    echo "Looking for alternative locations..."
    find ~/Library -name "neo4j.conf" -type f 2>/dev/null | head -5
    exit 1
fi

echo "✅ Found Neo4j config at: $NEO4J_CONF"

# Backup the config
cp "$NEO4J_CONF" "$NEO4J_CONF.backup.$(date +%Y%m%d_%H%M%S)"
echo "✅ Created backup of neo4j.conf"

# Add GDS/GenAI configuration if not already present
echo "" >> "$NEO4J_CONF"
echo "# GenAI and GDS Configuration (added by Enliterator)" >> "$NEO4J_CONF"
echo "dbms.security.procedures.unrestricted=gds.*,genai.*,apoc.*" >> "$NEO4J_CONF"
echo "dbms.security.procedures.allowlist=gds.*,genai.*,apoc.*,db.*" >> "$NEO4J_CONF"
echo "dbms.unmanaged_extension_classes=com.neo4j.gds=/gds" >> "$NEO4J_CONF"
echo "dbms.security.allow_csv_import_from_file_urls=true" >> "$NEO4J_CONF"

echo "✅ Added GenAI/GDS configuration to neo4j.conf"
echo ""
echo "📋 Configuration added:"
tail -6 "$NEO4J_CONF"

echo ""
echo "⚠️  IMPORTANT: You must restart Neo4j for changes to take effect"
echo "   In Neo4j Desktop: Stop and Start your database"