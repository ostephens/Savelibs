#!/usr/bin/ruby
require 'rubygems'
require 'mechanize'
require 'nokogiri'
require 'open-uri'
require 'sucker'
require 'sru'
require 'rss'

class Librarysystem
    #superclass which describes a library system - just a name and url, as yet no methods
    def initialize(name, url, login, password)
    	@name = name
		@url = url
		@login = login
		@password = password
	end	
    attr_reader :name, :url, :login, :password
end

class Vubis < Librarysystem
    def initialize(name, url, login, password)
        super(name,url, login, password)
    end
    
    def loanHistory
        #this is where we retrieve the loan history and use it to create an array of loanitem objects
        litems = Array.new()
        a = Mechanize.new { |agent|
            agent.user_agent_alias = 'Mac Safari'
        }

        a.get(@url) do |login_page|
            login_frame = a.click(login_page.frame_with(:name => 'Body'))
            
            myaccount_page = login_frame.form_with(:name => 'Login') do |form|
                form.CardId = @login
                form.Pin = @password
            end.submit
            
            myaccount_frame = a.click(myaccount_page.frame_with(:name => 'Body'))
            
            loanhistory_page = a.click(myaccount_frame.link_with(:text => /My loan history/))
            
            loanhistory_frame = a.click(loanhistory_page.frame_with(:name => 'Body'))
            
            itemtable = loanhistory_frame.parser.xpath('//form/table[3]')
            
            itemtable.xpath('tr').each do |itemrow|
                if itemrow.xpath('td[1]').attribute("class").to_s == 'listhead'
                else
                    litems.push(Loanitem.new(itemrow.xpath('td[1]/div').inner_text.chop.strip,itemrow.xpath('td[2]/div').inner_text))
                end
            end
        end
    return litems
    end
end

class Loanitem
    def initialize(title, loandate)
        @title = title
        @loandate = loandate
    end
    
    attr_reader :title, :loandate
    attr_accessor :isbn, :price, :image, :authordesc, :amazurl, :liburl

    def to_s
        "Title: #{@title}  #{@authordesc}     Loan date: #{@loandate}"
    end
    
    def printLoanitem
        puts "-----------------------------  Item details  -----------------------------"
        puts @title
        puts @authordesc
        puts @isbn
        puts @loandate
        puts @image
        puts @price
        puts @amazurl
    end
    
    def wpCSVline
        wpdate = Date.strptime(@loandate, '%d/%m/%Y')
        puts "\"#{@title} - #{@loandate}\",\"<a href=\"\"#{@amazurl}\"\"><img src=\"\"#{@image}\"\" /></a><br /><strong>Title:</strong> #{@title}<br /><strong>Author(s):</strong> #{@authordesc}<br /><strong>ISBN:</strong> #{@isbn}<br /><strong>Date of last Loan:</strong> #{@loandate}<br /><strong>Price:</strong> #{@price}<br /><a href=\"\"http://www.librarything.com/addbooks.php?search=#{@isbn}\"\">Add to LibraryThing</a> (make sure you are logged into the right account!)<br /><a href=\"\"#{@amazurl}\"\">Purchase on Amazon</a>\",\"\",\"\",\"\",\"borrowername\",\"#{wpdate}\",\"\",\"\",\"#{@title}\",\"#{@authdesc}\",\"#{@isbn}\",\"#{@price}\""
    end
end

class Loanlist
   def initialize
       @loans = Array.new
   end
   
   def addLoan(aLoanitem)
       @loans.push(aLoanitem)
       self
   end
   
   def rssLoanlist
       rss = RSS::Maker.make("1.0") do |maker|
           maker.channel.about = "http://www.meanboyfriend.com/"
           maker.channel.title = "Books"
           maker.channel.link = "http://www.meanboyfriend.com/"
           maker.channel.description = "Books"

           #	maker.items.do_sort = true

           @loans.each do |litem|
               maker.items.new_item do |item|
                   item.link = litem.liburl
                   # Wordpress syndication uses title as unique key for posts - so need something to differentiate between reviews with same title - perhaps use date? Currently prog.date just stored as text string
                   item.title = litem.title
                   item.date = Date.parse(litem.loandate)
                   item.description = litem.isbn
                   item.author = litem.authordesc
               end
           end
       end
       puts rss
   end

   def printLoanlist
        @loans.each do |litem|
            litem.printLoanitem
        end
    end
    
    def wpCSV
        puts '"csv_post_title","csv_post_post","csv_post_type","csv_post_excerpt","csv_post_categories","csv_post_tags","csv_post_date","csv_post_author","csv_post_slug","title","author(s)","isbn","price"'
        @loans.each do |litem|
            litem.wpCSVline
        end
    end
end

class Enhancebib
    def initialize(loanitem)
        @loanitem = loanitem
    end
end

class Aquabrowsersru < Enhancebib
    def initialize(loanitem,url)
        super(loanitem)
        @url = url
    end
    
    def getCreator
        # create the client using a base address for the SRU service
        client = SRU::Client.new(@url)

        # issue a search and get back a SRU::SearchRetrieveResponse object
        # which serves as an iterator
        records = client.search_retrieve @loanitem.title, {:version => '1.1',:maximumRecords => 1}
        pp records.number_of_records
        records.each do |record|
            if record.elements["dc:creator"] 
                @loanitem.authordesc = record.elements["dc:creator"].text
            end
        end
    end
    
    # http://librarycatalogue.warwickshire.gov.uk/ABwarwick/sru.ashx?operation=searchRetrieve&version=1.1&query=dogs&maximumRecords=100&recordSchema=dc
    # http://librarycatalogue.warwickshire.gov.uk/ABwarwick/result.ashx?q=cats&output=xml
    # branch=LEA
    # http://librarycatalogue.warwickshire.gov.uk/abwarwick/fullrecordinnerframe.ashx?hreciid=|library/vubissmart-marc|494187&output=xml
    
end

class Aquabrowserxml < Enhancebib
    def initialize(loanitem,url)
        super(loanitem)
        @url = url
    end
    
    #Got SRU working, but returns v limited information
    #Might need to swap to xml interface
    #http://librarycatalogue.warwickshire.gov.uk/ABwarwick/result.ashx?q=cats&branch=LEA&output=xml
    
    # Link to item in Library catalogue
    # http://librarycatalogue.warwickshire.gov.uk/ABwarwick/Accessible.ashx?cmd=frec&hreciid=|library/vubissmart-marc|263184
    
    def expandEnhance
        litems = Array.new()
        match = 0
        docurl = URI.escape(@url + "&q=" + @loanitem.title)
        doc = Nokogiri::XML(open(docurl))
    	doc.xpath("//record").each do |bibrec|
    	    if @loanitem.title.gsub(/[^a-zA-Z ]/, '') == bibrec.xpath("fields/title").inner_text.strip.gsub(/[^a-zA-Z ]/, '')
    	        litem = Loanitem.new(bibrec.xpath("fields/title").inner_text.strip,@loanitem.loandate)
                litem.isbn = bibrec.xpath("fields/isbn").inner_text.slice(/(?:ISBN(?:-1[03])?:? )?(?=[-0-9 ]{17}\b|[-0-9X ]{13}\b|[0-9X]{10}\b)(?:97[89][- ]?)?[0-9]{1,5}[- ]?(?:[0-9]+[- ]?){2}[0-9X]/)
                litem.authordesc = bibrec.xpath("fields/author").inner_text
                litem.image = bibrec.xpath("coverimageurl").inner_text
                litem.liburl = "http://librarycatalogue.warwickshire.gov.uk/ABwarwick/Accessible.ashx?cmd=frec&hreciid=" + bibrec.attribute("extID")
                litems.push(litem)
                match = 1
            end
    	end
    	if match == 0
            litem = Loanitem.new(@loanitem.title,@loanitem.loandate)
            litems.push(litem)
        end
        
    return litems
    end
    
    # http://librarycatalogue.warwickshire.gov.uk/ABwarwick/sru.ashx?operation=searchRetrieve&version=1.1&query=dogs&maximumRecords=100&recordSchema=dc
    # http://librarycatalogue.warwickshire.gov.uk/ABwarwick/result.ashx?q=cats&output=xml
    # branch=LEA
    # http://librarycatalogue.warwickshire.gov.uk/abwarwick/fullrecordinnerframe.ashx?hreciid=|library/vubissmart-marc|494187&output=xml
    
end


class Amazon < Enhancebib
    def initialize(loanitem)
        super(loanitem)
    end
    
    def amazEnhance
        #will retrieve amazon price here
        #trying http://www.rdoc.info/github/papercavalier/sucker/master/file/README.md

        #check what information we have first
        #isbn better search than title
        #title + author better than just title
        #title last resort
        
        #can we put multiple values in ItemSearch? e.g. {'Title' => @title, 'Author' => @author, 'ISBN' => @isbn} ?
        #what happens if any of these empty?
        
        #For this to work you need an Amazon Web Services account and then replace 'API KEY' and 'API SECRET' below with real values
        worker = Sucker.new(
            :locale => :uk,
            :key => 'API KEY',
            :secret => 'API SECRET'
            )
        if @loanitem.isbn     
            worker << {
                "Operation" =>  'ItemSearch',
                "SearchIndex" => 'Books',
                "Power" => 'isbn:' + @loanitem.isbn,
                "ResponseGroup" => 'ItemAttributes',
                "ItemPage" => '1'
            }
    
            amazon_response = worker.get
            begin
                if amazon_response.valid?
                    if amazon_response.find('CurrencyCode')[0] == "GBP"
                        @loanitem.price = amazon_response.find('Amount')[0].to_f / 100
                    end
                    @loanitem.amazurl = amazon_response.find('DetailPageURL')[0]
                end
            rescue
                #something here
            end
            
            
        end
    end
end

#Main
listory = Array.new
expandedlistory = Array.new
loans = Loanlist.new
# To get a loan history, add substitute <barcode> and <pin> with real values
library = Vubis.new('warks','https://library.warwickshire.gov.uk/vs/Pa.csp?OpacLanguage=eng&Profile=Default','<barcode>','<pin>')
listory = library.loanHistory

listory.each do |litem|
    aqenhance = Aquabrowserxml.new(litem,'http://librarycatalogue.warwickshire.gov.uk/ABwarwick/result.ashx?branch=LEA&output=xml')
    expandedlistory.concat(aqenhance.expandEnhance)
end

expandedlistory.each do |litem|
    # this doesn't feel right ... need to restructure objects/methods?
    aenhance = Amazon.new(litem)
    aenhance.amazEnhance
    loans.addLoan(litem)
end

loans.wpCSV
        