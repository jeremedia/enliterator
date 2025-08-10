module MarkdownHelper
  def render_markdown(text)
    return "" if text.blank?
    
    # Lazy load the markdown renderer
    markdown_renderer.render(text).html_safe
  end
  
  private
  
  def markdown_renderer
    @markdown_renderer ||= begin
      require 'redcarpet'
      require 'rouge'
      require 'rouge/plugins/redcarpet'
      
      renderer = Class.new(Redcarpet::Render::HTML) do
        include Rouge::Plugins::Redcarpet
        
        def block_code(code, language)
          # Add copy button to code blocks
          <<~HTML
            <div class="relative group my-4">
              <pre class="bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto">#{super}</pre>
              <button class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity p-2 bg-gray-800 rounded hover:bg-gray-700 text-gray-300" 
                      data-action="click->chat#copyCode"
                      data-code="#{ERB::Util.html_escape(code)}"
                      title="Copy code">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                </svg>
              </button>
            </div>
          HTML
        end
        
        def paragraph(text)
          %(<p class="mb-3">#{text}</p>)
        end
        
        def header(text, level)
          classes = case level
          when 1 then "text-2xl font-bold mt-6 mb-3"
          when 2 then "text-xl font-bold mt-6 mb-3"
          when 3 then "text-lg font-semibold mt-4 mb-2"
          else "font-semibold mt-3 mb-2"
          end
          %(<h#{level} class="#{classes}">#{text}</h#{level}>)
        end
        
        def list(content, list_type)
          classes = list_type == :ordered ? "list-decimal" : "list-disc"
          %(<#{list_type == :ordered ? 'ol' : 'ul'} class="#{classes} ml-6 my-2 space-y-1">#{content}</#{list_type == :ordered ? 'ol' : 'ul'}>)
        end
        
        def link(link, title, content)
          %(<a href="#{link}" class="text-indigo-600 hover:text-indigo-800 underline" target="_blank" rel="noopener" title="#{title}">#{content}</a>)
        end
        
        def codespan(code)
          %(<code class="bg-gray-100 px-1.5 py-0.5 rounded text-sm font-mono text-gray-800">#{ERB::Util.html_escape(code)}</code>)
        end
      end
      
      Redcarpet::Markdown.new(
        renderer.new(
          filter_html: true,
          no_images: false,
          no_links: false,
          no_styles: true,
          safe_links_only: true,
          with_toc_data: true
        ),
        autolink: true,
        tables: true,
        fenced_code_blocks: true,
        disable_indented_code_blocks: true,
        strikethrough: true,
        lax_spacing: true,
        space_after_headers: true,
        superscript: true,
        underline: true,
        highlight: true,
        quote: true,
        footnotes: true
      )
    end
  end
end