require 'action_view/helpers/tag_helper'
require 'i18n/exceptions'

module I18n
  class ExceptionHandler
    include Module.new {
      def call(exception, locale, key, options)
        exception.is_a?(MissingTranslation) && options[:rescue_format] == :html ? super.html_safe : super
      end
    }
  end
end

module ActionView
  # = Action View Translation Helpers
  module Helpers
    module TranslationHelper
      # Delegates to <tt>I18n#translate</tt> but also performs three additional functions.
      #
      # First, it'll pass the <tt>:rescue_format => :html</tt> option to I18n so that any
      # thrown +MissingTranslation+ messages will be turned into inline spans that
      #
      #   * have a "translation-missing" class set,
      #   * contain the missing key as a title attribute and
      #   * a titleized version of the last key segment as a text.
      #
      # E.g. the value returned for a missing translation key :"blog.post.title" will be
      # <span class="translation_missing" title="translation missing: en.blog.post.title">Title</span>.
      # This way your views will display rather reasonable strings but it will still
      # be easy to spot missing translations.
      #
      # Second, it'll scope the key by the current partial if the key starts
      # with a period. So if you call <tt>translate(".foo")</tt> from the
      # <tt>people/index.html.erb</tt> template, you'll actually be calling
      # <tt>I18n.translate("people.index.foo")</tt>. This makes it less repetitive
      # to translate many keys within the same partials and gives you a simple framework
      # for scoping them consistently. If you don't prepend the key with a period,
      # nothing is converted.
      #
      # Third, it'll mark the translation as safe HTML if the key has the suffix
      # "_html" or the last element of the key is the word "html". For example,
      # calling translate("footer_html") or translate("footer.html") will return
      # a safe HTML string that won't be escaped by other HTML helper methods. This
      # naming convention helps to identify translations that include HTML tags so that
      # you know what kind of output to expect when you call translate in a template.
      # Note however that rule extends to interpolated values, so you are responsible
      # for passing them already escaped in the call, if they need to be.
      def translate(key, options = {})
        options.merge!(:rescue_format => :html) unless options.key?(:rescue_format)
        translation = I18n.translate(scope_key_by_partial(key), options)
        if html_safe_translation_key?(key) && translation.respond_to?(:html_safe)
          translation.html_safe
        else
          translation
        end
      end
      alias :t :translate

      # Delegates to <tt>I18n.localize</tt> with no additional functionality.
      def localize(*args)
        I18n.localize(*args)
      end
      alias :l :localize

      private
        def scope_key_by_partial(key)
          if key.to_s.first == "."
            if @virtual_path
              @virtual_path.gsub(%r{/_?}, ".") + key.to_s
            else
              raise "Cannot use t(#{key.inspect}) shortcut because path is not available"
            end
          else
            key
          end
        end

        def html_safe_translation_key?(key)
          key.to_s =~ /(\b|_|\.)html$/
        end
    end
  end
end
