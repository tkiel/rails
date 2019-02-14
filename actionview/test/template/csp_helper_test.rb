# frozen_string_literal: true

require "abstract_unit"

class CspHelperWithCspEnabledTest < ActionView::TestCase
  tests ActionView::Helpers::CspHelper

  def content_security_policy_nonce
    "iyhD0Yc0W+c="
  end

  def content_security_policy?
    true
  end

  def test_csp_meta_tag
    assert_equal "<meta name=\"csp-nonce\" content=\"iyhD0Yc0W+c=\" />", csp_meta_tag
  end
end

class CspHelperWithCspDisabledTest < ActionView::TestCase
  tests ActionView::Helpers::CspHelper

  def content_security_policy?
    false
  end

  def test_csp_meta_tag
    assert_nil csp_meta_tag
  end
end
