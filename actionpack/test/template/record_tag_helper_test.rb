require 'abstract_unit'
require 'controller/fake_models'

class Post
  extend ActiveModel::Naming
  include ActiveModel::Conversion
  def id
     45
  end
  def body
    super || "What a wonderful world!"
  end
end

class RecordTagHelperTest < ActionView::TestCase
  tests ActionView::Helpers::RecordTagHelper

  def setup
    super
    @post = Post.new
    @post.persisted = true
  end

  def test_content_tag_for
    expected = %(<li class="post bar" id="post_45"></li>)
    actual = content_tag_for(:li, @post, :class => 'bar') { }
    assert_dom_equal expected, actual
  end

  def test_content_tag_for_prefix
    expected = %(<ul class="archived_post" id="archived_post_45"></ul>)
    actual = content_tag_for(:ul, @post, :archived) { }
    assert_dom_equal expected, actual
  end

  def test_content_tag_for_with_extra_html_tags
    expected = %(<tr class="post bar" id="post_45" style='background-color: #f0f0f0'></tr>)
    actual = content_tag_for(:tr, @post, {:class => "bar", :style => "background-color: #f0f0f0"}) { }
    assert_dom_equal expected, actual
  end

  def test_block_not_in_erb_multiple_calls
    expected = %(<div class="post bar" id="post_45">#{@post.body}</div>)
    actual = div_for(@post, :class => "bar") { @post.body }
    assert_dom_equal expected, actual
    actual = div_for(@post, :class => "bar") { @post.body }
    assert_dom_equal expected, actual
  end

  def test_block_works_with_content_tag_for_in_erb
    expected = %(<tr class="post" id="post_45">#{@post.body}</tr>)
    actual = content_tag_for(:tr, @post) { concat @post.body }
    assert_dom_equal expected, actual
  end

  def test_div_for_in_erb
    expected = %(<div class="post bar" id="post_45">#{@post.body}</div>)
    actual = div_for(@post, :class => "bar") { concat @post.body }
    assert_dom_equal expected, actual
  end
end
