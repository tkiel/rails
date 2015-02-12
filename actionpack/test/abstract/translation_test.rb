require 'abstract_unit'

module AbstractController
  module Testing
    class TranslationController < AbstractController::Base
      include AbstractController::Translation
    end

    class TranslationControllerTest < ActiveSupport::TestCase
      def setup
        @controller = TranslationController.new
        I18n.backend.store_translations(:en, {
          one: {
            two: 'bar',
          },
          abstract_controller: {
            testing: {
              translation: {
                index: {
                  foo: 'bar',
                },
                no_action: 'no_action_tr',
              },
            },
          },
        })
        @controller.stubs(action_name: :index)
      end

      def test_action_controller_base_responds_to_translate
        assert_respond_to @controller, :translate
      end

      def test_action_controller_base_responds_to_t
        assert_respond_to @controller, :t
      end

      def test_action_controller_base_responds_to_localize
        assert_respond_to @controller, :localize
      end

      def test_action_controller_base_responds_to_l
        assert_respond_to @controller, :l
      end

      def test_lazy_lookup
        assert_equal 'bar', @controller.t('.foo')
      end

      def test_lazy_lookup_with_symbol
        assert_equal 'bar', @controller.t(:'.foo')
      end

      def test_lazy_lookup_fallback
        assert_equal 'no_action_tr', @controller.t(:'.no_action')
      end

      def test_default_translation
        assert_equal 'bar', @controller.t('one.two')
      end

      def test_localize
        time, expected = Time.gm(2000), 'Sat, 01 Jan 2000 00:00:00 +0000'
        I18n.stubs(:localize).with(time).returns(expected)
        assert_equal expected, @controller.l(time)
      end
    end
  end
end
