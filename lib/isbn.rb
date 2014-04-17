#----------
#  ISBN utilities
#        by Travis J I Corcoran 
#        tjic@rubyrailsexpert.com
#
#  ISBNs (International Standard Book Numbers) define a namespace and
#  a number standard for books.
#
#  ISBNs come in multiple varieties, which can cause problems. e.g.:
#  you may have data that says that book X has ISBN Y, but when you
#  scan the barcode on the back of book X, you get number Z.  How do
#  you compare a scanned number to a number you received from some
#  third party?
#
#  This gem provides utilities to translate ISBNs.
#
#  First, an overview of ISBN varieties:
#
#  
#      10 digits: ISBN10
#           * 9 data digits
#           * 1 check digit
#   
#      12 digits: ISBN10 + 2-digit suplement
#            * 9 digits data
#            * ??
#   
#      13 digits: ISBN13 / EAN13 (which is a superset of UPC-13...)
#            * 3 digits EAN prefix ("Bookland" = "978" or "979")
#            * 9 ISBN data digits
#            * 1 check digit (using a different algorithm from above!)
#            
#      15 digits: ISBN10 + 5-digit suplement
#            * 9 digits data
#            * 1 digit currency code (5 = USD, 0 = UKB)
#            * 4 digit price
#   
#      18 digits:
#             * 13 digits: ISBN13
#             * 5 digits: EAN 5 (price info)
#
# How to use this library
# ------------------------
#
#  This library provides tools to convert any format to 13 digits, at
#  which point ISBNs from disparate sources can be compared, e.g.
#  
#     Isbn.convert_to_13("978123456789051299") == Isbn.convert_to_13("1234567890")
#
#
# references
#------------
# http://www.barcodeisland.com/upcext.phtml
# https://en.wikipedia.org/wiki/European_Article_Number
# https://en.wikipedia.org/wiki/EAN_5
# https://en.wikipedia.org/wiki/EAN_13
# https://en.wikipedia.org/wiki/ISBN


# situation at HeavyInk.com
#---------------
# Diamond solicitations           : ISBN10   (mostly)
# Diamond website                 : ISBN13+5 (mostly)
# Our scanner returns             : ISBN13 / ISBN13+5 / 14chars
# Google wants                    : 10 / 13
# our canonical db representation : ISBN13


class Isbn
  @@verbose = false

  ISBN_10_REGEXP = "^[0-9]{10}$"
  ISBN_13_REGEXP = "^[0-9]{13}$"

  ISBN_13_FAKE = "9739999999996"

  #----------
  #  10 digits
  #----------


  # 1) remove "bookland" prefix, if present
  # 2) remove price code at end, if present
  def self.scanned_to_isbn10(scanned)
    scanned.gsub(/^978/, "")[0,10] if scanned
  end

  # http://www.isbn.org/standards/home/isbn/international/html/usm4.htm
  #
  # The check digit is the last digit of an ISBN. It is calculated on
  # a modulus 11 with weights 10-2, using X in lieu of 10 where ten
  # would occur as a check digit.
  # 
  # This means that each of the first nine digits of the ISBN –
  # excluding the check digit itself – is multiplied by a number
  # ranging from 10 to 2 and that the resulting sum of the products,
  # plus the check digit, must be divisible by 11 without a remainder.

  def self.isbn10_checksum(isbn)
    raise "need 10 digits - got #{isbn.size}" if isbn.size != 10
    ret = 0
    weight = 9


    input = isbn[1,8]
    puts "input = #{input}" if @@verbose
    input.split("").map(&:to_i).each do |x|
      ret += x * weight
      puts "byte #{x} x weight #{weight} = #{x * weight} ; total = #{ret}" if @@verbose
      weight -= 1
    end
    checksum = 11 - (ret % 11)
    checksum = "X" if checksum == 10 
    puts "checksum = #{checksum}" if @@verbose
    checksum
  end

  # test:
  #   true   == Isbn.isbn10_verify("0843610727")
  #   false  == Isbn.isbn10_verify("0843610728")
  def self.isbn10_verify(isbn)
    checksum = isbn10_checksum(isbn)
    bit = isbn[9,1].to_i

    puts "bit = #{bit}" if @@verbose
    puts "checksum = #{checksum}" if @@verbose

    checksum == bit
  end

  # 1) prepend bookland
  # 2) rewrite checksum
  def self.convert_10_to_13(isbn)
    raise "need 10 digits - got #{isbn.size}" if isbn.size != 10
    isbn = "978" + isbn
    isbn[12] = isbn13_checksum(isbn).to_s
    isbn
  end


  #----------
  #  13 digits
  #----------

  # 1) insert "bookland" prefix, unless present
  # 2) remove price code at end, if present
  def self.scanned_to_isbn13(scanned)
    return nil unless scanned
    scanned = ("978" + scanned) unless scanned[0,3] == "978"
    scanned = scanned[0,13]
    scanned

  end


  # http://www.morovia.com/education/symbology/ean-13.asp
  #
  # EAN check digit is calculated using standard Mod10 method. Here
  # outlines the steps to calculate EAN-13 check digit:
  #
  # 1) From the right to left, start with odd position, assign the
  #    odd/even position to each digit.
  # 2) Sum all digits in odd position and multiply the result by 3.
  # 3) Sum all digits in even position.
  # 4) Sum the results of step 3 and step 4.
  # 5) divide the result of step 4 by 10. The check digit is the
  #    number which adds the remainder to 10.
  #
  def self.isbn13_checksum(isbn)
    raise "need 13 digits - got #{isbn.size}" if isbn.size != 13

    bit = isbn[12,1].to_i
    isbn = isbn[0,12]

    odd_sum = even_sum = 0
    ii = 1
    puts "isbn = #{isbn}" if @@verbose
    isbn[0,12].split("").reverse.map(&:to_i).each do |x|
      even =  (ii % 2) == 0
      puts "#{ii} : #{ even ? 'eve' : 'odd' }  - #{x}" if @@verbose
      if even
        even_sum += x
      else
        odd_sum += x
      end
      ii += 1
    end

    checksum = (even_sum + odd_sum * 3) 
    checksum = checksum % 10
    checksum = 10 - checksum unless checksum == 0
    puts "checksum = #{checksum}" if @@verbose
    checksum
  end

  # test:
  #   true  == Isbn.isbn13_verify("9781595828057")
  #   false == Isbn.isbn13_verify("9781595828097")
  #   false == Isbn.isbn13_verify("9781595829958")
  
  def self.isbn13_verify(isbn)
    bit = isbn[12,1].to_i
    checksum = isbn13_checksum(isbn)
    # puts "bit = #{bit}"
    # puts "checksum = #{checksum}"
    checksum == bit
  end

  #----------
  #  14 digits
  #----------

  # scans as:         16001088571999
  # should read:  978 1600108853  // (5) 1999
  #
  # 1) chop off price
  # 2) convert 10 -> 13
  def self.convert_14_to_13(isbn)
    raise "unexpected 978" if isbn[0,3] == "978" 
    convert_10_to_13(isbn[0,10])
  end

  #----------
  #  18 digits
  #----------


  # chop off price
  def self.convert_18_to_13(isbn)
    raise "expected 978" unless isbn[0,3] == "978" 
    isbn[0,13]
  end

  #----------
  #  toplevel
  #----------

  def self.convert_to_13(input)

    input.gsub!(/\n/, "")
    output = nil

    if input.size == 10
      # good_10 = isbn10_verify(input)
      # output = convert_10_to_13(input)
      # good_13 = isbn13_verify(output)
      # puts "size 10 -> #{output} : #{good_10 ? 'GOOD' : 'BAD'} // #{good_13 ? 'GOOD' : 'BAD'}"

      puts "  size 10 -> not supported" if @@verbose
    elsif input.size == 13
      good = isbn13_verify(input)
      output = input
      puts "  size 13 -> #{output} : #{good ? 'GOOD' : 'BAD'}" if @@verbose
    elsif input.size == 14
      output = convert_14_to_13(input)
      good = isbn13_verify(output)
      puts "  size 18 -> #{output} : #{good ? 'GOOD' : 'BAD'}" if @@verbose
    elsif input.size == 17
      # this may be a UPC
      # 
      #    TODO: move this out of here to keep this a pure database-less ISBN library
      #    available for reuse by others
      #
      products = ItemCode.find_all_by_upc(input).map(&:product).reject { |gn| gn.replaced_by_id }.uniq
      raise "none found" unless products.any?
      raise "too many found: #{products.size} items for UPC #{input}" unless products.size == 1
      output = products.first.isbn_number
      puts "  size 18 -> #{output} : #{good ? 'GOOD' : 'BAD'}" if @@verbose
    elsif input.size == 18
      output = convert_18_to_13(input)
      good = isbn13_verify(output)
      puts "  size 18 -> #{output} : #{good ? 'GOOD' : 'BAD'}" if @@verbose
    else
      puts "  ERROR unknown size #{input.size} for #{input}"
    end

    output
  end



end
