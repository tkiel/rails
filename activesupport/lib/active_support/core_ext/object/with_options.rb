require 'active_support/option_merger'

class Object
  # An elegant way to factor duplication out of options passed to a series of
  # method calls. Each method called in the block, with the block variable as
  # the receiver, will have its options merged with the default +options+ hash
  # provided. Each method called on the block variable must take an options
  # hash as its final argument.
  #
  # Without <tt>with_options</tt>, this code contains duplication:
  #
  #   class Account < ActiveRecord::Base
  #     has_many :customers, dependent: :destroy
  #     has_many :products,  dependent: :destroy
  #     has_many :invoices,  dependent: :destroy
  #     has_many :expenses,  dependent: :destroy
  #   end
  #
  # Using <tt>with_options</tt>, we can remove the duplication:
  #
  #   class Account < ActiveRecord::Base
  #     with_options dependent: :destroy do |assoc|
  #       assoc.has_many :customers
  #       assoc.has_many :products
  #       assoc.has_many :invoices
  #       assoc.has_many :expenses
  #     end
  #   end
  #
  # It can also be used with an explicit receiver:
  #
  #   I18n.with_options locale: user.locale, scope: 'newsletter' do |i18n|
  #     subject i18n.t :subject
  #     body    i18n.t :body, user_name: user.name
  #   end
  #
  # When you don't pass an explicit receiver, it executes the whole block
  # in merging options context:
  #
  #   class Account < ActiveRecord::Base
  #     with_options dependent: :destroy do
  #       has_many :customers
  #       has_many :products
  #       has_many :invoices
  #       has_many :expenses
  #     end
  #   end
  #
  # <tt>with_options</tt> can also be nested since the call is forwarded to its receiver.
  #
  # NOTE: Each nesting level will merge inherited defaults in addition to their own.
  #
  #   class Post < ActiveRecord::Base
  #     with_options if: :persisted?, length: { minimum: 50 } do
  #       validates :content, if: -> { content.present? }
  #     end
  #   end
  #
  # The code is equivalent to:
  #
  #   validates :content, length: { minimum: 50 }, if: -> { content.present? }
  #
  # Hence the inherited default for `if` key is ignored.
  #
  def with_options(options, &block)
    option_merger = ActiveSupport::OptionMerger.new(self, options)
    block.arity.zero? ? option_merger.instance_eval(&block) : block.call(option_merger)
  end
end
