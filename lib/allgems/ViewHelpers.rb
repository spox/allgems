require 'rdoc/markup/to_html'

module AllGems
    module ViewHelpers
    
        def tag_options(options, escape = true)
            option_string = options.collect {|k,v| %{#{k}="#{v}"}}.join(' ')
            option_string = " " + option_string unless option_string.blank?
        end

        def content_tag(name, content, options, escape = true)
            tag_options = tag_options(options, escape) if options
            "<#{name}#{tag_options}>#{content}</#{name}>"
        end

        def link_to(text, link = nil, options = {})         
            link ||= text
            link = url_for(link)
            "<a href=\"#{link}\">#{text}</a>"
        end

        def link_to_gem(gem, options = {})
            version = options[:version] ? options[:version] : ''
            text = options[:text] ? options[:text] : gem
            link_to(text, "/gems/#{gem}/#{version}")
        end

        def url_for(link_options)
            case link_options
            when Hash
                path = link_options.delete(:path) || request.path_info
                params.delete('captures')
                path + '?' + build_query(params.merge(link_options))
            else
                link_options
            end
        end

        def ts(time)
            time.strftime('%b %d, %Y') if time
        end

        def rdocify(text)
            @_rdoc ||= RDoc::Markup::ToHtml.new
            @_rdoc.convert(text)
        end
    end
end