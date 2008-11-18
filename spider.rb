#!/usr/local/bin/ruby
require 'rubygems'
require 'mechanize'
require 'dm-core'
require 'db/link.rb'
require 'csv'
class Spider
  # Set defaults and pull args
  def initialize(options = {})
    @depth = options[:depth]
    @url = options[:url]
    @baseurl = 'http://www.madison.com'
    @counter = options[:counter] || 1
    @clean_start = options[:clean_start] || false
    @verbose = options[:verbose] || false
    @suppress_errors = options[:suppress_errors] || false
    @stylesheet = options[:stylesheet] || "default.css"
    @agent = WWW::Mechanize.new
    @page = @agent.get(@url)
    if @clean_start
      Link.auto_migrate!
    end
  end

  def crawl
    top = Thread.new do
    unless @counter > @depth
      @page.links.each do |link|
        next if link.href.nil?
        next if forbidden?(link.href)
        begin
          if link.href =~ /^http:\/\/w+\.madison.com/
            process_full_url(link.href)
          end
      
          if link.href =~ /^\//
            link.href.chop! if link.href=~ /\/$/
            process_relative_url(link.href)
          end
          
        rescue WWW::Mechanize::ResponseCodeError => rce
          case rce.response_code
          when '404'
            detail = 'Not Found'
          when '403'
            detail = 'Forbidden'
          else
            detail = 'Unknown error'
          end
          puts "Processing link has failed! Error code: #{rce.response_code} #{detail}" unless @suppress_errors
        rescue Timeout::Error
          puts "Skipping  #{@url}. Reason: Timed out while processing file." unless @suppress_errors
        rescue SystemCallError
          puts 'Timeout error. Skipping.'
        rescue URI::InvalidURIError
          puts "#{@url} is not a valid link. Ignoring." unless @suppress_errors
        end
      end 
    end
  end
  top.join
  end
  
  def generate_csv
    puts 'Generating CSV' if @verbose
    CSV.open('html/results.csv', 'w') do |csv|
      distinct = repository(:default).adapter.query('SELECT distinct url from links')
      distinct.each do |url|
        @line = ["#{url}"]
        Link.all(:conditions => ["url = ?", url]).each do |tag|
          @line << tag.tag
        end
        csv << @line
      end
    end
  end
  
  private
  
  def process_full_url(link)
    tabber = ''
    @counter.times{ tabber += '--' }
    unless exists?(link)
      puts "#{tabber}Processing #{link}" if @verbose
      db_save(link)
      new_thread = Thread.new do
        next_link = Spider.new(:url => link, :depth => @depth, :counter => @counter + 1, :verbose => @verbose, :suppress_errors => @suppress_errors)
          next_link.crawl
      end
      new_thread.join
    else 
      puts "Skipping #{link} Reason: Already Processed." unless @suppress_errors
    end
  end
  
  def process_relative_url(link)
    tabber = ''
    link = @baseurl + link
    @counter.times{ tabber += '--' }
    unless exists?(link)
      puts "#{tabber}Processing #{link}" if @verbose
      db_save(link)
      new_thread = Thread.new do
        next_link = Spider.new(:url => link, :depth => @depth, :counter => @counter + 1, :verbose => @verbose, :suppress_errors => @suppress_errors)
          next_link.crawl
      end
      new_thread.join
    else
      puts "Skipping #{link} Reason: Already Processed." unless @suppress_errors
    end
  end
  
  def db_save(link)
    tags = find_ad_tag(link)
    unless tags.nil?
      tags.each do |tag|
        page = Link.new
        page.attributes = {:url => link, :tag => tag}
        unless page.save do
          puts "There was an error saving the tag" unless @suppress_errors
        end
      end
      end
    end
  end
  
  def find_ad_tag(link)
    tags = Array.new
    adsearch = @agent.get(link)
    adsearch.search("//script[@language='JavaScript']").each do |block|
      if block.inner_html =~ /(what=zone:)/
        tags << block.inner_html.match(/zone:\d{3}/)[0] unless block.inner_html.match(/zone:\d{3}/).nil?
      end
    end
    tags.reject! {|t| t.empty?}
    return tags
  end
  
  def forbidden?(link)
    case link
    when nil, /\.xml/, /\.pdf/, /\.gif/, /\.jpg/, /^\/\{/, /rss.php$/
      return true
    else
      return false
    end
  end
  
  def exists?(link)
   exists = Link.first(:url => link)
   unless exists.nil?
     return true
   else
     return false
   end
  end
end

if __FILE__ == $0
  url = 'http://www.madison.com'
  @spider = Spider.new(:url => url, :depth => 6, :clean_start => false, :verbose => true, :suppress_errors => true)
 # @spider.crawl
  @spider.generate_csv
end
