module ActionText
  module Attribute
    extend ActiveSupport::Concern

    class_methods do
      def has_rich_text(name)
        class_eval <<-CODE, __FILE__, __LINE__ + 1
          def #{name}
            self.rich_text_#{name} ||= ActionText::RichText.new(name: "#{name}", record: self)
          end

          def #{name}=(body)
            #{name}.body = body
          end
        CODE

        has_one :"rich_text_#{name}", -> { where(name: name) }, class_name: "ActionText::RichText", as: :record, inverse_of: :record, dependent: false

        scope :"with_rich_text_#{name}", -> { includes("rich_text_#{name}") }

        after_save { public_send(name).save if public_send(name).changed? }
      end
    end
  end
end
