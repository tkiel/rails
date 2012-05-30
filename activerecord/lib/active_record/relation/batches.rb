require 'active_support/core_ext/object/blank'

module ActiveRecord
  module Batches
    # Looping through a collection of records from the database
    # (using the +all+ method, for example) is very inefficient
    # since it will try to instantiate all the objects at once.
    #
    # In that case, batch processing methods allow you to work
    # with the records in batches, thereby greatly reducing memory consumption.
    #
    # The <tt>find_each</tt> method uses <tt>find_in_batches</tt> with a batch size of 1000 (or as
    # specified by the <tt>:batch_size</tt> option).
    #
    #   Person.all.find_each do |person|
    #     person.do_awesome_stuff
    #   end
    #
    #   Person.where("age > 21").find_each do |person|
    #     person.party_all_night!
    #   end
    #
    #  You can also pass the <tt>:start</tt> option to specify
    #  an offset to control the starting point.
    def find_each(options = {})
      find_in_batches(options) do |records|
        records.each { |record| yield record }
      end
    end

    # Yields each batch of records that was found by the find +options+ as
    # an array. The size of each batch is set by the <tt>:batch_size</tt>
    # option; the default is 1000.
    #
    # You can control the starting point for the batch processing by
    # supplying the <tt>:start</tt> option. This is especially useful if you
    # want multiple workers dealing with the same processing queue. You can
    # make worker 1 handle all the records between id 0 and 10,000 and
    # worker 2 handle from 10,000 and beyond (by setting the <tt>:start</tt>
    # option on that worker).
    #
    # It's not possible to set the order. That is automatically set to
    # ascending on the primary key ("id ASC") to make the batch ordering
    # work. This also mean that this method only works with integer-based
    # primary keys. You can't set the limit either, that's used to control
    # the batch sizes.
    #
    #   Person.where("age > 21").find_in_batches do |group|
    #     sleep(50) # Make sure it doesn't get too crowded in there!
    #     group.each { |person| person.party_all_night! }
    #   end
    #
    #   # Let's process the next 2000 records
    #   Person.all.find_in_batches(start: 2000, batch_size: 2000) do |group|
    #     group.each { |person| person.party_all_night! }
    #   end
    def find_in_batches(options = {})
      options.assert_valid_keys(:start, :batch_size)

      relation = self

      unless arel.orders.blank? && arel.taken.blank?
        ActiveRecord::Base.logger.warn("Scoped order and limit are ignored, it's forced to be batch order and batch size")
      end

      start = options.delete(:start).to_i
      batch_size = options.delete(:batch_size) || 1000

      relation = relation.reorder(batch_order).limit(batch_size)
      records = relation.where(table[primary_key].gteq(start)).all

      while records.any?
        records_size = records.size
        primary_key_offset = records.last.id

        yield records

        break if records_size < batch_size

        if primary_key_offset
          records = relation.where(table[primary_key].gt(primary_key_offset)).to_a
        else
          raise "Primary key not included in the custom select clause"
        end
      end
    end

    private

    def batch_order
      "#{quoted_table_name}.#{quoted_primary_key} ASC"
    end
  end
end
