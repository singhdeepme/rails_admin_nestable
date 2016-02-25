module RailsAdmin
  module Config
    module Actions
      class Nestable < Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :pjax? do
          true
        end

        register_instance_option :root? do
          false
        end

        register_instance_option :collection? do
          true
        end

        register_instance_option :member? do
          false
        end

        register_instance_option :controller do
          Proc.new do |klass|
            @nestable_conf = ::RailsAdminNestable::Configuration.new @abstract_model
            @position_field = @nestable_conf.options[:position_field].to_s.split('.').last
            @enable_callback = @nestable_conf.options[:enable_callback]
            @nestable_scope = @nestable_conf.options[:scope]
            @options = @nestable_conf.options
            @adapter = @abstract_model.adapter

            # Methods
            def update_tree(tree_nodes, parent_node = nil)
              tree_nodes.each do |key, value|
                
                parent =  @abstract_model.model.parent_node.find(value['id'].to_s) if !parent_node
                update_tree(value['children'], parent) if value.has_key?('children')

                
                next if !parent_node
                model = @abstract_model.model
                parent_column = (model.parent_node.to_s+"_id".downcase).to_sym
                child_column = (model.child_node.to_s+"_id".downcase).to_sym

                model = model.where(parent_column => parent_node.id, child_column => value['id']).first

                #model = @abstract_model.model.where(get_id(@abstract_model.model.parent_node) parent_node.id, get_id(@abstract_model.model.child_node) value['id'].to_s)
                
                if @position_field.present? && parent_node
                  model.update({position: key.to_i + 1}) 
                  model.save!(validate: @enable_callback)
                end
                
              end
            end

            def update_list(model_list)
              model_list.each do |key, value|
                model = @abstract_model.model.find(value['id'].to_s)
                model.send("#{@position_field}=".to_sym, (key.to_i + 1))
                model.save!(validate: @enable_callback)
              end
            end

            if request.post? && params['tree_nodes'].present?
              begin
                update = ->{
                  update_tree params[:tree_nodes] if @nestable_conf.tree?
                  update_list params[:tree_nodes] if @nestable_conf.list?
                }

                ActiveRecord::Base.transaction { update.call } if @adapter == :active_record
                update.call if @adapter == :mongoid

                message = "<strong>#{I18n.t('admin.actions.nestable.success')}!</strong>"
              rescue Exception => e
                message = "<strong>#{I18n.t('admin.actions.nestable.error')}</strong>: #{e}"
              end

              render text: message
            end

            if request.get?
              query = list_entries(@model_config, :nestable, false, false).reorder(nil)

              case @options[:scope].class.to_s
                when 'Proc'
                  query.merge!(@options[:scope].call)
                when 'Symbol'
                  query.merge!(@abstract_model.model.public_send(@options[:scope]))
              end

              if @nestable_conf.tree?
                @tree_nodes = if @options[:position_field].present?
                  query.arrange(order: @options[:position_field])
                else
                  query.arrange
                end
              end

              if @nestable_conf.list?
                @tree_nodes = query.order("#{@options[:position_field]} ASC")
              end

              render action: @action.template_name
            end
          end
        end

        register_instance_option :link_icon do
          'icon-move fa fa-arrows'
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :visible? do
          current_model = ::RailsAdmin::Config.model(bindings[:abstract_model])
          authorized? && (current_model.nestable_tree || current_model.nestable_list)
        end
      end
    end
  end
end
