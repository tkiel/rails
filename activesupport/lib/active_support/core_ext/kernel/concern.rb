# frozen_string_literal: true

require_relative "../module/concerning"

module Kernel
  module_function

  # A shortcut to define a toplevel concern, not within a module.
  #
  # See Module::Concerning for more.
  def concern(topic, &module_definition)
    Object.concern topic, &module_definition
  end
end
