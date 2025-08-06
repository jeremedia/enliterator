// VisualizationManager - Orchestrates the creation and management of visualizations
// This is the bridge between conversation and visual representation

import { RelationshipGraph } from 'navigator/visualizations/relationship_graph';

class VisualizationManager {
  constructor() {
    this.activeVisualizations = new Map();
    this.visualizationCounter = 0;
    this.canvas = null;
    this.canvasWelcome = null;
    this.activeVisualizationsContainer = null;
    
    this.init();
  }
  
  init() {
    // Get canvas elements
    this.canvas = document.getElementById('visualization-canvas');
    this.canvasWelcome = document.getElementById('canvas-welcome');
    this.activeVisualizationsContainer = document.getElementById('active-visualizations');
    
    // Listen for visualization requests from the Navigator
    window.addEventListener('create-visualization', (event) => {
      this.handleVisualizationRequest(event.detail);
    });
    
    // Listen for node selection events
    window.addEventListener('graph-node-selected', (event) => {
      this.handleNodeSelection(event.detail);
    });
  }
  
  handleVisualizationRequest(request) {
    const { type, data, query } = request;
    
    switch(type) {
      case 'relationship_graph':
        this.createRelationshipGraph(data, query);
        break;
      case 'timeline':
        // TODO: Implement timeline visualization
        console.log('Timeline visualization requested but not yet implemented');
        break;
      case 'comparison_chart':
        // TODO: Implement comparison chart
        console.log('Comparison chart requested but not yet implemented');
        break;
      default:
        console.warn(`Unknown visualization type: ${type}`);
    }
  }
  
  createRelationshipGraph(graphData, query) {
    // Hide welcome message if it's the first visualization
    if (this.activeVisualizations.size === 0) {
      this.canvasWelcome.classList.add('hidden');
      this.activeVisualizationsContainer.classList.remove('hidden');
    }
    
    // Create container for this visualization
    const vizId = `viz-${++this.visualizationCounter}`;
    const vizContainer = this.createVisualizationContainer(vizId, 'Relationship Graph', query);
    
    // Add to active visualizations grid
    this.activeVisualizationsContainer.appendChild(vizContainer);
    
    // Get the graph container within the visualization window
    const graphContainer = vizContainer.querySelector('.visualization-content');
    
    // Create the D3 graph
    const graph = new RelationshipGraph(graphContainer, graphData, {
      width: graphContainer.clientWidth,
      height: 400
    });
    
    // Render the graph
    graph.render();
    
    // Store reference
    this.activeVisualizations.set(vizId, {
      type: 'relationship_graph',
      instance: graph,
      container: vizContainer,
      query: query
    });
    
    // Update canvas status
    this.updateCanvasStatus(`Showing ${this.activeVisualizations.size} visualization${this.activeVisualizations.size > 1 ? 's' : ''}`);
    
    // Announce the visualization creation
    this.announceVisualization('relationship_graph', graphData);
  }
  
  createVisualizationContainer(id, title, query) {
    const container = document.createElement('div');
    container.id = id;
    container.className = 'visualization-window bg-white rounded-lg shadow-lg border border-slate-200 flex flex-col';
    container.innerHTML = `
      <div class="visualization-header px-4 py-2 bg-slate-50 border-b border-slate-200 flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
          </svg>
          <h3 class="text-sm font-medium text-slate-700">${title}</h3>
          <span class="text-xs text-slate-500">• ${query}</span>
        </div>
        <div class="flex items-center space-x-1">
          <button class="p-1 rounded hover:bg-slate-200" title="Minimize" data-action="minimize">
            <svg class="w-3 h-3 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4" />
            </svg>
          </button>
          <button class="p-1 rounded hover:bg-slate-200" title="Maximize" data-action="maximize">
            <svg class="w-3 h-3 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
            </svg>
          </button>
          <button class="p-1 rounded hover:bg-slate-200" title="Close" data-action="close">
            <svg class="w-3 h-3 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
      <div class="visualization-content flex-1 p-4">
        <!-- Graph will be rendered here -->
      </div>
      <div class="visualization-footer px-4 py-2 bg-slate-50 border-t border-slate-200 text-xs text-slate-600">
        Click nodes to explore • Drag to rearrange • Scroll to zoom
      </div>
    `;
    
    // Add event listeners for window controls
    container.querySelector('[data-action="close"]').addEventListener('click', () => {
      this.closeVisualization(id);
    });
    
    container.querySelector('[data-action="minimize"]').addEventListener('click', () => {
      this.minimizeVisualization(id);
    });
    
    container.querySelector('[data-action="maximize"]').addEventListener('click', () => {
      this.maximizeVisualization(id);
    });
    
    return container;
  }
  
  closeVisualization(id) {
    const viz = this.activeVisualizations.get(id);
    if (viz) {
      viz.container.remove();
      this.activeVisualizations.delete(id);
      
      // Show welcome if no visualizations left
      if (this.activeVisualizations.size === 0) {
        this.canvasWelcome.classList.remove('hidden');
        this.activeVisualizationsContainer.classList.add('hidden');
      }
      
      this.updateCanvasStatus(
        this.activeVisualizations.size > 0 
          ? `Showing ${this.activeVisualizations.size} visualization${this.activeVisualizations.size > 1 ? 's' : ''}`
          : 'Ready for visualizations'
      );
    }
  }
  
  minimizeVisualization(id) {
    const viz = this.activeVisualizations.get(id);
    if (viz) {
      viz.container.querySelector('.visualization-content').classList.toggle('hidden');
      viz.container.querySelector('.visualization-footer').classList.toggle('hidden');
    }
  }
  
  maximizeVisualization(id) {
    const viz = this.activeVisualizations.get(id);
    if (viz) {
      // Toggle between grid and full-screen
      viz.container.classList.toggle('lg:col-span-2');
      viz.container.classList.toggle('row-span-2');
      
      // Resize the graph if it's a relationship graph
      if (viz.type === 'relationship_graph' && viz.instance) {
        setTimeout(() => {
          const content = viz.container.querySelector('.visualization-content');
          viz.instance.options.width = content.clientWidth;
          viz.instance.options.height = content.clientHeight;
          viz.instance.render();
        }, 300);
      }
    }
  }
  
  handleNodeSelection(detail) {
    const { node, connected, graphId } = detail;
    
    // Show entity inspector
    const inspector = document.getElementById('entity-inspector');
    const inspectorContent = document.querySelector('[data-navigator-target="inspectorContent"]');
    
    if (inspector && inspectorContent) {
      inspector.classList.remove('hidden');
      
      inspectorContent.innerHTML = `
        <div class="space-y-3">
          <div>
            <h4 class="text-lg font-medium text-slate-900">${node.label}</h4>
            <span class="inline-block px-2 py-1 text-xs rounded-full ${this.getPoolColorClass(node.pool)}">
              ${node.pool}
            </span>
          </div>
          
          <div>
            <h5 class="text-sm font-medium text-slate-700 mb-1">Properties</h5>
            <dl class="text-xs space-y-1">
              ${Object.entries(node.properties || {}).map(([key, value]) => `
                <div class="flex justify-between">
                  <dt class="text-slate-500">${key}:</dt>
                  <dd class="text-slate-700">${value}</dd>
                </div>
              `).join('')}
            </dl>
          </div>
          
          <div>
            <h5 class="text-sm font-medium text-slate-700 mb-1">Connected Entities</h5>
            <p class="text-xs text-slate-600">${connected.length - 1} direct connections</p>
          </div>
          
          <div class="pt-2 border-t border-slate-200">
            <button class="w-full px-3 py-1.5 bg-blue-500 text-white text-xs rounded hover:bg-blue-600">
              Explore connections
            </button>
          </div>
        </div>
      `;
    }
  }
  
  getPoolColorClass(pool) {
    const classes = {
      'Idea': 'bg-red-100 text-red-700',
      'Manifest': 'bg-teal-100 text-teal-700',
      'Experience': 'bg-blue-100 text-blue-700',
      'Relational': 'bg-green-100 text-green-700',
      'Evolutionary': 'bg-yellow-100 text-yellow-700',
      'Practical': 'bg-purple-100 text-purple-700',
      'Emanation': 'bg-pink-100 text-pink-700',
      'Spatial': 'bg-cyan-100 text-cyan-700',
      'Evidence': 'bg-amber-100 text-amber-700',
      'Intent': 'bg-sky-100 text-sky-700'
    };
    return classes[pool] || 'bg-gray-100 text-gray-700';
  }
  
  updateCanvasStatus(message) {
    const statusElement = document.querySelector('[data-navigator-target="canvasStatus"]');
    if (statusElement) {
      statusElement.textContent = message;
    }
  }
  
  announceVisualization(type, data) {
    // Send event to Navigator to announce what was created
    window.dispatchEvent(new CustomEvent('visualization-created', {
      detail: {
        type: type,
        nodeCount: data.nodes ? data.nodes.length : 0,
        edgeCount: data.relationships ? data.relationships.length : 0
      }
    }));
  }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  window.visualizationManager = new VisualizationManager();
});

export default VisualizationManager;