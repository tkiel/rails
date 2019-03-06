# frozen_string_literal: true

require "cases/helper"
require "models/book"

class ReadonlyNameBook < Book
  attr_readonly :name
end

class InsertAllTest < ActiveRecord::TestCase
  fixtures :books

  def test_insert
    assert_difference "Book.count", +1 do
      Book.insert! name: "Rework", author_id: 1
    end
  end

  def test_insert_all
    assert_difference "Book.count", +10 do
      Book.insert_all! [
        { name: "Rework", author_id: 1 },
        { name: "Patterns of Enterprise Application Architecture", author_id: 1 },
        { name: "Design of Everyday Things", author_id: 1 },
        { name: "Practical Object-Oriented Design in Ruby", author_id: 1 },
        { name: "Clean Code", author_id: 1 },
        { name: "Ruby Under a Microscope", author_id: 1 },
        { name: "The Principles of Product Development Flow", author_id: 1 },
        { name: "Peopleware", author_id: 1 },
        { name: "About Face", author_id: 1 },
        { name: "Eloquent Ruby", author_id: 1 },
      ]
    end
  end

  def test_insert_all_should_handle_empty_arrays
    assert_raise ArgumentError do
      Book.insert_all! []
    end
  end

  def test_insert_all_raises_on_duplicate_records
    assert_raise ActiveRecord::RecordNotUnique do
      Book.insert_all! [
        { name: "Rework", author_id: 1 },
        { name: "Patterns of Enterprise Application Architecture", author_id: 1 },
        { name: "Agile Web Development with Rails", author_id: 1 },
      ]
    end
  end

  def test_insert_all_returns_ActiveRecord_Result
    result = Book.insert_all! [{ name: "Rework", author_id: 1 }]
    assert_kind_of ActiveRecord::Result, result
  end

  def test_insert_all_returns_primary_key_if_returning_is_supported
    skip unless supports_insert_returning?

    result = Book.insert_all! [{ name: "Rework", author_id: 1 }]
    assert_equal %w[ id ], result.columns
  end

  def test_insert_all_returns_nothing_if_returning_is_empty
    skip unless supports_insert_returning?

    result = Book.insert_all! [{ name: "Rework", author_id: 1 }], returning: []
    assert_equal [], result.columns
  end

  def test_insert_all_returns_nothing_if_returning_is_false
    skip unless supports_insert_returning?

    result = Book.insert_all! [{ name: "Rework", author_id: 1 }], returning: false
    assert_equal [], result.columns
  end

  def test_insert_all_returns_requested_fields
    skip unless supports_insert_returning?

    result = Book.insert_all! [{ name: "Rework", author_id: 1 }], returning: [:id, :name]
    assert_equal %w[ Rework ], result.pluck("name")
  end

  def test_insert_all_can_skip_duplicate_records
    skip unless supports_insert_on_duplicate_skip?

    assert_no_difference "Book.count" do
      Book.insert_all [{ id: 1, name: "Agile Web Development with Rails" }]
    end
  end

  def test_insert_all_will_raise_if_duplicates_are_skipped_only_for_a_certain_conflict_target
    skip unless supports_insert_on_duplicate_skip? && supports_insert_conflict_target?

    assert_raise ActiveRecord::RecordNotUnique do
      Book.insert_all [{ id: 1, name: "Agile Web Development with Rails" }],
        unique_by: { columns: %i{author_id name} }
    end
  end

  def test_upsert_all_updates_existing_records
    skip unless supports_insert_on_duplicate_update?

    new_name = "Agile Web Development with Rails, 4th Edition"
    Book.upsert_all [{ id: 1, name: new_name }]
    assert_equal new_name, Book.find(1).name
  end

  def test_upsert_all_does_not_update_readonly_attributes
    skip unless supports_insert_on_duplicate_update?

    new_name = "Agile Web Development with Rails, 4th Edition"
    ReadonlyNameBook.upsert_all [{ id: 1, name: new_name }]
    assert_not_equal new_name, Book.find(1).name
  end

  def test_upsert_all_does_not_update_primary_keys
    skip unless supports_insert_on_duplicate_update? && supports_insert_conflict_target?

    Book.upsert_all [{ id: 101, name: "Perelandra", author_id: 7 }]
    Book.upsert_all [{ id: 103, name: "Perelandra", author_id: 7, isbn: "1974522598" }],
      unique_by: { columns: %i{author_id name} }

    book = Book.find_by(name: "Perelandra")
    assert_equal 101, book.id, "Should not have updated the ID"
    assert_equal "1974522598", book.isbn, "Should have updated the isbn"
  end

  def test_upsert_all_does_not_perform_an_upsert_if_a_partial_index_doesnt_apply
    skip unless supports_insert_on_duplicate_update? && supports_insert_conflict_target? && supports_partial_index?

    Book.upsert_all [{ name: "Out of the Silent Planet", author_id: 7, isbn: "1974522598", published_on: Date.new(1938, 4, 1) }]
    Book.upsert_all [{ name: "Perelandra", author_id: 7, isbn: "1974522598" }],
      unique_by: { columns: %w[ isbn ], where: "published_on IS NOT NULL" }

    assert_equal ["Out of the Silent Planet", "Perelandra"], Book.where(isbn: "1974522598").order(:name).pluck(:name)
  end
end
