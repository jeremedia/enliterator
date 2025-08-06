// RelationshipGraph - Force-directed graph visualization for showing entity relationships
// This is what makes it a Knowledge Navigator, not a chatbot

import * as d3 from 'd3';

export class RelationshipGraph {
  constructor(container, data, options = {}) {
    this.container = container;
    this.data = this.processGraphData(data);
    this.options = {
      width: options.width || container.clientWidth || 600,
      height: options.height || container.clientHeight || 400,
      nodeRadius: options.nodeRadius || 8,
      linkDistance: options.linkDistance || 100,
      chargeStrength: options.chargeStrength || -300,
      ...options
    };
    
    this.simulation = null;
    this.svg = null;
    this.g = null;
    this.link = null;
    this.node = null;
    this.label = null;
    this.selectedNode = null;
  }
  
  processGraphData(neoData) {
    // Convert Neo4j result format to D3 format
    const nodes = (neoData.nodes || []).map(n => ({
      id: n.id,
      label: n.name || n.label || `Entity ${n.id}`,
      pool: n.type || n.pool || 'Unknown',
      properties: n.properties || {},
      radius: Math.sqrt(n.connection_count || 1) * 5,
      x: null,
      y: null
    }));
    
    const links = (neoData.relationships || neoData.edges || []).map(r => ({
      source: r.start || r.source,
      target: r.end || r.target,
      type: r.type || r.relationship || 'RELATES_TO',
      properties: r.properties || {},
      strength: r.weight || 1
    }));
    
    return { nodes, links };
  }
  
  render() {
    // Clear any existing visualization
    d3.select(this.container).selectAll("*").remove();
    
    // Create SVG
    this.svg = d3.select(this.container)
      .append("svg")
      .attr("width", this.options.width)
      .attr("height", this.options.height)
      .attr("class", "relationship-graph");
    
    // Add zoom behavior
    const zoom = d3.zoom()
      .scaleExtent([0.1, 10])
      .on("zoom", (event) => {
        this.g.attr("transform", event.transform);
      });
    
    this.svg.call(zoom);
    
    // Create main group
    this.g = this.svg.append("g");
    
    // Create arrow markers for directed edges
    this.svg.append("defs").selectAll("marker")
      .data(["arrow"])
      .enter().append("marker")
      .attr("id", d => d)
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 20)
      .attr("refY", 0)
      .attr("markerWidth", 8)
      .attr("markerHeight", 8)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,-5L10,0L0,5")
      .attr("fill", "#999");
    
    // Create force simulation
    this.simulation = d3.forceSimulation(this.data.nodes)
      .force("link", d3.forceLink(this.data.links)
        .id(d => d.id)
        .distance(this.options.linkDistance))
      .force("charge", d3.forceManyBody()
        .strength(this.options.chargeStrength))
      .force("center", d3.forceCenter(this.options.width / 2, this.options.height / 2))
      .force("collision", d3.forceCollide().radius(d => d.radius + 5));
    
    // Create links
    this.link = this.g.append("g")
      .attr("class", "links")
      .selectAll("line")
      .data(this.data.links)
      .enter().append("line")
      .attr("stroke", "#999")
      .attr("stroke-opacity", 0.6)
      .attr("stroke-width", d => Math.sqrt(d.strength))
      .attr("marker-end", "url(#arrow)");
    
    // Create link labels
    const linkLabel = this.g.append("g")
      .attr("class", "link-labels")
      .selectAll("text")
      .data(this.data.links)
      .enter().append("text")
      .attr("font-size", "9px")
      .attr("fill", "#666")
      .attr("text-anchor", "middle")
      .text(d => d.type);
    
    // Create nodes
    this.node = this.g.append("g")
      .attr("class", "nodes")
      .selectAll("circle")
      .data(this.data.nodes)
      .enter().append("circle")
      .attr("r", d => d.radius || this.options.nodeRadius)
      .attr("fill", d => this.getColorForPool(d.pool))
      .attr("stroke", "#fff")
      .attr("stroke-width", 2)
      .style("cursor", "pointer")
      .call(this.drag());
    
    // Add hover effect
    this.node
      .on("mouseenter", (event, d) => {
        this.highlightNode(d);
      })
      .on("mouseleave", () => {
        this.unhighlightAll();
      })
      .on("click", (event, d) => {
        event.stopPropagation();
        this.onNodeClick(d);
      });
    
    // Create labels
    this.label = this.g.append("g")
      .attr("class", "labels")
      .selectAll("text")
      .data(this.data.nodes)
      .enter().append("text")
      .text(d => d.label)
      .attr("font-size", "11px")
      .attr("dx", 12)
      .attr("dy", 4)
      .style("pointer-events", "none");
    
    // Add title tooltips
    this.node.append("title")
      .text(d => `${d.label} (${d.pool})`);
    
    // Start simulation
    this.simulation.on("tick", () => {
      this.link
        .attr("x1", d => d.source.x)
        .attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x)
        .attr("y2", d => d.target.y);
      
      linkLabel
        .attr("x", d => (d.source.x + d.target.x) / 2)
        .attr("y", d => (d.source.y + d.target.y) / 2);
      
      this.node
        .attr("cx", d => d.x)
        .attr("cy", d => d.y);
      
      this.label
        .attr("x", d => d.x)
        .attr("y", d => d.y);
    });
    
    // Click on background to deselect
    this.svg.on("click", () => {
      this.deselectNode();
    });
  }
  
  getColorForPool(pool) {
    const colors = {
      'Idea': '#FF6B6B',
      'Manifest': '#4ECDC4',
      'Experience': '#45B7D1',
      'Relational': '#96CEB4',
      'Evolutionary': '#FFEAA7',
      'Practical': '#DDA0DD',
      'Emanation': '#FFB6C1',
      'Spatial': '#98D8C8',
      'Evidence': '#F7DC6F',
      'Intent': '#85C1E2',
      'Unknown': '#95A5A6'
    };
    return colors[pool] || colors['Unknown'];
  }
  
  highlightNode(node) {
    const connected = this.getConnectedNodes(node);
    
    // Fade non-connected nodes
    this.node.style("opacity", d => connected.has(d) ? 1 : 0.3);
    this.label.style("opacity", d => connected.has(d) ? 1 : 0.3);
    
    // Highlight connected links
    this.link
      .style("opacity", d => 
        (d.source === node || d.target === node) ? 1 : 0.1)
      .attr("stroke-width", d => 
        (d.source === node || d.target === node) ? 2 : 1);
  }
  
  unhighlightAll() {
    this.node.style("opacity", 1);
    this.label.style("opacity", 1);
    this.link
      .style("opacity", 0.6)
      .attr("stroke-width", d => Math.sqrt(d.strength));
  }
  
  onNodeClick(node) {
    this.selectedNode = node;
    
    // Highlight connected nodes more prominently
    const connected = this.getConnectedNodes(node);
    
    this.node
      .style("opacity", d => connected.has(d) ? 1 : 0.2)
      .attr("stroke", d => d === node ? "#333" : "#fff")
      .attr("stroke-width", d => d === node ? 3 : 2);
    
    // Send event to Navigator
    window.dispatchEvent(new CustomEvent('graph-node-selected', {
      detail: { 
        node: node,
        connected: Array.from(connected),
        graphId: this.container.id
      }
    }));
  }
  
  deselectNode() {
    this.selectedNode = null;
    this.unhighlightAll();
    this.node
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);
    
    window.dispatchEvent(new CustomEvent('graph-node-deselected', {
      detail: { graphId: this.container.id }
    }));
  }
  
  getConnectedNodes(node) {
    const connected = new Set([node]);
    
    this.data.links.forEach(link => {
      if (link.source === node || link.source.id === node.id) {
        connected.add(link.target);
      }
      if (link.target === node || link.target.id === node.id) {
        connected.add(link.source);
      }
    });
    
    return connected;
  }
  
  filterByPool(poolName) {
    // Filter nodes and links by pool type
    const filteredNodes = poolName === 'all' 
      ? this.data.nodes 
      : this.data.nodes.filter(n => n.pool === poolName);
    
    const nodeIds = new Set(filteredNodes.map(n => n.id));
    const filteredLinks = this.data.links.filter(l => 
      nodeIds.has(l.source.id || l.source) && 
      nodeIds.has(l.target.id || l.target)
    );
    
    // Update visualization with filtered data
    this.updateData({ nodes: filteredNodes, links: filteredLinks });
  }
  
  updateData(newData) {
    // Update the graph with new data
    this.data = this.processGraphData(newData);
    
    // Restart simulation with new data
    this.simulation.nodes(this.data.nodes);
    this.simulation.force("link").links(this.data.links);
    this.simulation.alpha(1).restart();
    
    // Re-render
    this.render();
  }
  
  drag() {
    return d3.drag()
      .on("start", (event, d) => {
        if (!event.active) this.simulation.alphaTarget(0.3).restart();
        d.fx = d.x;
        d.fy = d.y;
      })
      .on("drag", (event, d) => {
        d.fx = event.x;
        d.fy = event.y;
      })
      .on("end", (event, d) => {
        if (!event.active) this.simulation.alphaTarget(0);
        // Keep node fixed after dragging
        // Uncomment next two lines to release node after dragging
        // d.fx = null;
        // d.fy = null;
      });
  }
  
  // Export as image
  exportAsImage(filename = 'knowledge-graph.png') {
    // Implementation for exporting the graph as PNG
    const svgData = new XMLSerializer().serializeToString(this.svg.node());
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    const img = new Image();
    
    canvas.width = this.options.width;
    canvas.height = this.options.height;
    
    img.onload = () => {
      ctx.fillStyle = 'white';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0);
      
      canvas.toBlob(blob => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
      });
    };
    
    img.src = 'data:image/svg+xml;base64,' + btoa(svgData);
  }
}

// Make it available globally for easy access
window.RelationshipGraph = RelationshipGraph;