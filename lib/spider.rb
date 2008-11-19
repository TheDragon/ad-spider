#!/usr/bin/env ruby

$LOAD_PATH.unshift File.dirname(__FILE__)

# Dependencies
require 'rubygems'
require 'csv'
require 'dm-core'
require 'mechanize'

# Core
require 'link'

class Spider
  # Set defaults and pull args
  def initialize(options = {})
    @depth = options[:depth] || 6
    @url = options[:url]
    @debug = options[:debug] || false
    @baseurl = 'http://www.madison.com'
    @counter = options[:counter] || 1
    @clean_start = options[:clean_start] || false
    @verbose = options[:verbose] || false
    @suppress_errors = options[:suppress_errors] || true
    @stylesheet = options[:stylesheet] || 'default.css'
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
          puts link.href.inspect
          next if link.href.nil?
          next if forbidden?(link.href)
          process_url(link.href)
          puts catch_errors unless catch_errors.nil?
        end
      end
    end
    top.join
  end
  
  private
  
  def process_url(link)
    puts "::::::::::DEBUG::::::::::#{link}" if @debug
    tabber = ''
    case link
    when /^http:\/\/\w+\.*madison\.com/
      link.sub!(/\/$/)
      run_thread(link)
    when /^\//
      link = @baseurl + link
      run_thread(link)
    when /^\w+/
      @url.sub!(/\/\w*\.\w{3}$/, '')
      link = "#{@url}/#{link}"
      run_thread(link)
    end
  end
  
  def run_thread(link)
    @counter.times{ tabber += '--' }
    unless exists?(link)
      puts "#{tabber}Processing #{link}" if @verbose
      db_save(link)
      new_thread = Thread.new do
        next_link = Spider.new(:url => link, :depth => @depth, :counter => @counter + 1, :verbose => @verbose, :suppress_errors => @suppress_errors, :debug => @debug)
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
  
  def find_ad_tag(link)
    tags = Array.new
    adsearch = @agent.get(link)
    adsearch.search("//script[@language='JavaScript']").each do |block|
      if block.inner_html =~ /(what=zone:)/
        found = block.inner_html.match(/zone:\d{3}/)
        tags << found[0] unless found.nil?
      end
    end
    tags.reject! {|t| t.empty?}
    return tags
  end
  
  def forbidden?(link)
    case link
    when nil, /\.xml$/, /\.pdf$/, /\.gif$/, /\.jpg$/, /^\/\{/, /rss.php$/, /^javascript:/
      return true
    when /^http:\/\/\w+\.*.madison\.com/
      return false
    when /^http:\/\//, /^https:\/\//
      return true
    else
      return false
    end
  end
  
  def exists?(link)
    Link.first(:url => link).nil? ? true : false
  end
  
  def catch_errors
    rescue WWW::Mechanize::ResponseCodeError => rce
      case rce.response_code
      when '404'
        detail = 'Not Found'
      when '403'
        detail = 'Forbidden'
      else
        detail = 'Unknown Error'
      end
      return "Processing #{@url} has failed! Error code: #{rce.response_code} #{detail}" unless @suppress_errors
    rescue Timeout::Error
      return "Skipping #{@url}. Reason: Timed out while processing link." unless @suppress_errors
    rescue SystemCallError
      return 'Timeout error. Skipping.'
    rescue URI::InvalidURIError
      return "#{@url} is not a valid link. Ignoring." unless @suppress_errors
    end
  end
end
url = 'http://www.madison.com'
spider = Spider.new(:url => url, :depth => 6, :clean_start => true, :verbose => true)
spider.crawl