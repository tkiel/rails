require 'date'
require 'active_support/core_ext/time/calculations'

class String
  # Converts a string to a Time value.
  # The +form+ can be either :utc or :local (default :local).
  #
  # The time is parsed using Time.parse method.
  # If +form+ is :local, then the time is in the system timezone.
  # If the date part is missing then the current date is used and if
  # the time part is missing then it is assumed to be 00:00:00.
  #
  #   "13-12-2012".to_time               # => 2012-12-13 00:00:00 +0100
  #   "06:12".to_time                    # => 2012-12-13 06:12:00 +0100
  #   "2012-12-13 06:12".to_time         # => 2012-12-13 06:12:00 +0100
  #   "2012-12-13T06:12".to_time         # => 2012-12-13 06:12:00 +0100
  #   "2012-12-13T06:12".to_time(:utc)   # => 2012-12-13 05:12:00 UTC
  def to_time(form = :local)
    parts = Date._parse(self, false)
    return if parts.empty?

    now = Time.now
    offset = parts[:offset]
    utc_offset = form == :utc ? 0 : now.utc_offset
    adjustment = offset ? offset - utc_offset : 0

    Time.send(
      form,
      parts.fetch(:year, now.year),
      parts.fetch(:mon, now.month),
      parts.fetch(:mday, now.day),
      parts.fetch(:hour, 0),
      parts.fetch(:min, 0),
      parts.fetch(:sec, 0) + parts.fetch(:sec_fraction, 0)
    ) - adjustment
  end

  # Converts a string to a Date value.
  #
  #   "1-1-2012".to_date   #=> Sun, 01 Jan 2012
  #   "01/01/2012".to_date #=> Sun, 01 Jan 2012
  #   "2012-12-13".to_date #=> Thu, 13 Dec 2012
  #   "12/13/2012".to_date #=> ArgumentError: invalid date
  def to_date
    ::Date.parse(self, false) unless blank?
  end

  # Converts a string to a DateTime value.
  #
  #   "1-1-2012".to_datetime            #=> Sun, 01 Jan 2012 00:00:00 +0000
  #   "01/01/2012 23:59:59".to_datetime #=> Sun, 01 Jan 2012 23:59:59 +0000
  #   "2012-12-13 12:50".to_datetime    #=> Thu, 13 Dec 2012 12:50:00 +0000
  #   "12/13/2012".to_datetime          #=> ArgumentError: invalid date
  def to_datetime
    unless blank?
      date_values = ::Date._parse(self, false).
        values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :sec_fraction).
        map! { |arg| arg || 0 }
      date_values[5] += date_values.pop

      ::DateTime.civil(*date_values)
    end
  end
end
