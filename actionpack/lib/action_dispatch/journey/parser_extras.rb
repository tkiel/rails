# frozen_string_literal: true

require_relative "scanner"
require_relative "nodes/node"

module ActionDispatch
  # :stopdoc:
  module Journey
    class Parser < Racc::Parser
      include Journey::Nodes

      def self.parse(string)
        new.parse string
      end

      def initialize
        @scanner = Scanner.new
      end

      def parse(string)
        @scanner.scan_setup(string)
        do_parse
      end

      def next_token
        @scanner.next_token
      end
    end
  end
  # :startdoc:
end
