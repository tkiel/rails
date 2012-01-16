module ActionView
  module Helpers
    module Tags
      autoload :BaseTag,      'action_view/helpers/tags/base_tag'
      autoload :LabelTag,     'action_view/helpers/tags/label_tag'
      autoload :TextFieldTag, 'action_view/helpers/tags/text_field_tag'
    end
  end
end
