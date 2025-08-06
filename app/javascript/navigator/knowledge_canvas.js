// KnowledgeCanvas - The visual workspace for the Knowledge Navigator
// This is where knowledge becomes visible and interactive

import { RelationshipGraph } from 'navigator/visualizations/relationship_graph';

class KnowledgeCanvas {
  constructor(container) {
    this.container = container;
    this.visualizations = new Map();
    this.vizCounter = 0;
    this.activeViz = null;
    this.init();
  }
  
  init() {
    this.setupEventListeners();
    this.createCanvasLayout();
  }
  
  setupEventListeners() {
    // Listen for visualization requests
    window.addEventListener('render-visualization', (event) => {
      this.addVisualization(event.detail);
    });
    
    // Listen for canvas commands
    window.addEventListener('canvas-command', (event) => {
      this.handleCommand(event.detail);
    });
  }
  
  createCanvasLayout() {
    if (!this.container) return;
    
    this.container.innerHTML = `
      <div class="knowledge-canvas h-full flex flex-col">
        <div class="canvas-header px-4 py-2 bg-slate-100 border-b flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <svg class="w-5 h-5 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
            <h3 class="text-sm font-medium text-slate-700">Knowledge Canvas</h3>
            <span class="text-xs text-slate-500 canvas-status">Ready</span>
          </div>
          <div class="flex items-center space-x-2">
            <button class="px-2 py-1 text-xs rounded hover:bg-slate-200 canvas-clear" title="Clear all">
              Clear All
            </button>
            <button class="px-2 py-1 text-xs rounded hover:bg-slate-200 canvas-arrange" title="Auto-arrange">
              Auto Arrange
            </button>
          </div>
        </div>
        
        <div class="canvas-workspace flex-1 overflow-auto p-4">
          <div class="canvas-welcome text-center py-12 text-slate-500">
            <svg class="w-16 h-16 mx-auto mb-4 text-slate-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
            <p class="text-sm">Ask a question about relationships to see them visualized</p>
            <p class="text-xs mt-2">Try: "Show me how the pipeline stages connect"</p>
          </div>
          
          <div class="visualizations-grid grid gap-4 hidden">
            <!-- Visualizations will be added here -->
          </div>
        </div>
        
        <div class="canvas-footer px-4 py-2 bg-slate-50 border-t text-xs text-slate-600 flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <span class="viz-count">No visualizations</span>
            <span class="node-count"></span>
          </div>
          <div class="flex items-center space-x-2">
            <button class="px-2 py-1 rounded hover:bg-slate-200 export-btn" title="Export view">
              Export
            </button>
          </div>
        </div>
      </div>
    `;
    
    // Bind event handlers
    this.container.querySelector('.canvas-clear')?.addEventListener('click', () => {
      this.clearAll();
    });
    
    this.container.querySelector('.canvas-arrange')?.addEventListener('click', () => {
      this.autoArrange();
    });
    
    this.container.querySelector('.export-btn')?.addEventListener('click', () => {
      this.exportCanvas();
    });
  }
  
  addVisualization(data) {
    const { type, vizData, query, options = {} } = data;
    
    // Hide welcome message
    const welcome = this.container.querySelector('.canvas-welcome');
    const grid = this.container.querySelector('.visualizations-grid');
    if (welcome) welcome.classList.add('hidden');
    if (grid) grid.classList.remove('hidden');
    
    // Create visualization container
    const vizId = `viz-${++this.vizCounter}`;
    const vizContainer = this.createVizContainer(vizId, type, query);
    
    // Add to grid
    const grid2 = this.container.querySelector('.visualizations-grid');
    if (grid2) grid2.appendChild(vizContainer);
    
    // Create the appropriate visualization
    let viz = null;
    const contentEl = vizContainer.querySelector('.viz-content');
    
    switch(type) {
      case 'network':
      case 'relationship_graph':
        viz = new NetworkVisualization(contentEl, vizData, options);
        break;
      case 'timeline':
        viz = new TimelineVisualization(contentEl, vizData, options);
        break;
      case 'tree':
        viz = new TreeVisualization(contentEl, vizData, options);
        break;
      default:
        // Fallback to network
        viz = new NetworkVisualization(contentEl, vizData, options);
    }
    
    if (viz) {
      viz.render();
      this.visualizations.set(vizId, {
        id: vizId,
        type: type,
        instance: viz,
        container: vizContainer,
        query: query
      });
      
      this.activeViz = vizId;
      this.updateStatus();
    }
    
    return vizId;
  }
  
  createVizContainer(id, type, query) {
    const container = document.createElement('div');
    container.id = id;
    container.className = 'viz-container bg-white rounded-lg shadow-sm border';
    
    container.innerHTML = `
      <div class="viz-header px-3 py-2 bg-slate-50 border-b flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <span class="text-xs font-medium text-slate-700">${this.getVizTitle(type)}</span>
          <span class="text-xs text-slate-500">• ${query.substring(0, 30)}...</span>
        </div>
        <div class="flex items-center space-x-1">
          <button class="p-1 rounded hover:bg-slate-200 viz-minimize" title="Minimize">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4" />
            </svg>
          </button>
          <button class="p-1 rounded hover:bg-slate-200 viz-maximize" title="Maximize">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
            </svg>
          </button>
          <button class="p-1 rounded hover:bg-slate-200 viz-close" title="Close">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
      <div class="viz-content" style="height: 400px;">
        <!-- Visualization renders here -->
      </div>
    `;
    
    // Bind control buttons
    container.querySelector('.viz-close')?.addEventListener('click', () => {
      this.removeVisualization(id);
    });
    
    container.querySelector('.viz-minimize')?.addEventListener('click', () => {
      const content = container.querySelector('.viz-content');
      content.classList.toggle('hidden');
      container.classList.toggle('minimized');
    });
    
    container.querySelector('.viz-maximize')?.addEventListener('click', () => {
      container.classList.toggle('maximized');
      container.classList.toggle('col-span-2');
      container.classList.toggle('row-span-2');
      
      // Trigger resize on the visualization
      const viz = this.visualizations.get(id);
      if (viz?.instance?.resize) {
        setTimeout(() => viz.instance.resize(), 300);
      }
    });
    
    return container;
  }
  
  getVizTitle(type) {
    const titles = {
      'network': 'Network Graph',
      'relationship_graph': 'Relationships',
      'timeline': 'Timeline',
      'tree': 'Hierarchy',
      'chart': 'Chart',
      'map': 'Spatial Map'
    };
    return titles[type] || 'Visualization';
  }
  
  removeVisualization(id) {
    const viz = this.visualizations.get(id);
    if (viz) {
      viz.container.remove();
      this.visualizations.delete(id);
      
      if (this.activeViz === id) {
        this.activeViz = null;
      }
      
      // Show welcome if no visualizations left
      if (this.visualizations.size === 0) {
        const welcome = this.container.querySelector('.canvas-welcome');
        const grid = this.container.querySelector('.visualizations-grid');
        if (welcome) welcome.classList.remove('hidden');
        if (grid) grid.classList.add('hidden');
      }
      
      this.updateStatus();
    }
  }
  
  clearAll() {
    if (confirm('Clear all visualizations?')) {
      this.visualizations.forEach((viz, id) => {
        this.removeVisualization(id);
      });
    }
  }
  
  autoArrange() {
    // Auto-arrange visualizations in grid
    const grid = this.container.querySelector('.visualizations-grid');
    if (grid) {
      // Reset all maximized visualizations
      this.visualizations.forEach(viz => {
        viz.container.classList.remove('maximized', 'col-span-2', 'row-span-2');
      });
      
      // Ensure grid layout
      grid.className = 'visualizations-grid grid gap-4 grid-cols-1 lg:grid-cols-2';
    }
  }
  
  updateStatus() {
    const count = this.visualizations.size;
    const vizCount = this.container.querySelector('.viz-count');
    if (vizCount) {
      vizCount.textContent = count === 0 ? 'No visualizations' : 
                            count === 1 ? '1 visualization' : 
                            `${count} visualizations`;
    }
    
    // Update node count
    let totalNodes = 0;
    let totalEdges = 0;
    this.visualizations.forEach(viz => {
      if (viz.instance?.data) {
        totalNodes += viz.instance.data.nodes?.length || 0;
        totalEdges += viz.instance.data.links?.length || 0;
      }
    });
    
    const nodeCount = this.container.querySelector('.node-count');
    if (nodeCount && totalNodes > 0) {
      nodeCount.textContent = `${totalNodes} nodes, ${totalEdges} relationships`;
    }
  }
  
  exportCanvas() {
    // Export all visualizations as a report
    const report = {
      timestamp: new Date().toISOString(),
      visualizations: Array.from(this.visualizations.values()).map(viz => ({
        type: viz.type,
        query: viz.query,
        nodeCount: viz.instance?.data?.nodes?.length || 0,
        edgeCount: viz.instance?.data?.links?.length || 0
      }))
    };
    
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `knowledge-canvas-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }
  
  handleCommand(command) {
    switch(command.action) {
      case 'focus':
        this.focusVisualization(command.vizId);
        break;
      case 'filter':
        this.filterVisualization(command.vizId, command.filter);
        break;
      case 'update':
        this.updateVisualization(command.vizId, command.data);
        break;
    }
  }
  
  focusVisualization(id) {
    const viz = this.visualizations.get(id);
    if (viz) {
      // Bring to front
      viz.container.scrollIntoView({ behavior: 'smooth', block: 'center' });
      viz.container.classList.add('ring-2', 'ring-blue-500');
      setTimeout(() => {
        viz.container.classList.remove('ring-2', 'ring-blue-500');
      }, 2000);
    }
  }
  
  filterVisualization(id, filter) {
    const viz = this.visualizations.get(id);
    if (viz?.instance?.filter) {
      viz.instance.filter(filter);
    }
  }
  
  updateVisualization(id, data) {
    const viz = this.visualizations.get(id);
    if (viz?.instance?.update) {
      viz.instance.update(data);
    }
  }
}

// Wrapper for NetworkVisualization using RelationshipGraph
class NetworkVisualization {
  constructor(container, data, options) {
    this.graph = new RelationshipGraph(container, data, options);
    this.data = data;
  }
  
  render() {
    this.graph.render();
  }
  
  resize() {
    const container = this.graph.container;
    this.graph.options.width = container.clientWidth;
    this.graph.options.height = container.clientHeight;
    this.graph.render();
  }
  
  filter(filterOptions) {
    if (filterOptions.pool) {
      this.graph.filterByPool(filterOptions.pool);
    }
  }
  
  update(newData) {
    this.graph.updateData(newData);
  }
}

// Placeholder for Timeline visualization
class TimelineVisualization {
  constructor(container, data, options) {
    this.container = container;
    this.data = data;
    this.options = options;
  }
  
  render() {
    this.container.innerHTML = `
      <div class="flex items-center justify-center h-full text-slate-400">
        <div class="text-center">
          <svg class="w-12 h-12 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <p class="text-sm">Timeline visualization coming soon</p>
        </div>
      </div>
    `;
  }
}

// Placeholder for Tree visualization
class TreeVisualization {
  constructor(container, data, options) {
    this.container = container;
    this.data = data;
    this.options = options;
  }
  
  render() {
    this.container.innerHTML = `
      <div class="flex items-center justify-center h-full text-slate-400">
        <div class="text-center">
          <svg class="w-12 h-12 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
          <p class="text-sm">Tree visualization coming soon</p>
        </div>
      </div>
    `;
  }
}

// Initialize when DOM is ready
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => {
    const canvasContainer = document.getElementById('knowledge-canvas');
    if (canvasContainer) {
      window.knowledgeCanvas = new KnowledgeCanvas(canvasContainer);
    }
  });
}

export { KnowledgeCanvas };
export default KnowledgeCanvas;