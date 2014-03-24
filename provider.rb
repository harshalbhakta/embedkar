# Reference: https://github.com/judofyr/ruby-oembed

require 'yaml'
require 'uri'
require 'open-uri'
require 'net/http'
require 'json'
require 'opengraph'

providers = []
providers.concat YAML::load(File.open('providers/oembed.yml'))
providers.concat YAML::load(File.open('providers/opengraph.yml'))
providers.concat YAML::load(File.open('providers/scrape.yml'))

# http://*.*
# https://*.*
urls = [ "https://www.goodreads.com/book/show/1141797", 
        "http://www.imdb.com/title/tt1155076/", 
        "https://www.youtube.com/watch?v=Ke1Y3P9D0Bc" ]

def url_to_regex(url)
  if !url.is_a?(Regexp)
    full, scheme, domain, path = *url.match(%r{([^:]*)://?([^/?]*)(.*)})
    domain = Regexp.escape(domain).gsub("\\*", "(.*?)").gsub("(.*?)\\.", "([^\\.]+\\.)?")
    path = Regexp.escape(path).gsub("\\*", "(.*?)")
    url = Regexp.new("^#{Regexp.escape(scheme)}://#{domain}#{path}")
  end
  url
end

def find_provider(providers,url)
  
  providers.each do |provider|
    url_scheme = provider["url_schemes"].detect { |x| url_to_regex(x) =~ url }
    if url_scheme != nil
      return provider
    end
  end

  nil
end

def extract_json_for_oembed_link(url,provider)
  
  uri = URI.parse(provider["endpoint"])

  found = false
  max_redirects = 4
  until found
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    
    %w{scheme userinfo host port registry}.each { |method| uri.send("#{method}=", nil) }
    res = http.request(Net::HTTP::Get.new(uri.to_s + "?url=" + url ))
    
    #res = Net::HTTP.start(uri.host, uri.port) {|http| http.get(uri.request_uri) }
    
    res.header['location'] ? uri = URI.parse(res.header['location']) : found = true
    if max_redirects == 0
      found = true
    else
      max_redirects -= 1
    end
  end
  
  case res
  when Net::HTTPNotImplemented
    raise OEmbed::UnknownFormat, format
  when Net::HTTPNotFound
    raise OEmbed::NotFound, url
  when Net::HTTPSuccess
    JSON.parse(res.body)
  else
    raise OEmbed::UnknownResponse, res && res.respond_to?(:code) ? res.code : 'Error'
  end

  rescue StandardError
    # Convert known errors into OEmbed::UnknownResponse for easy catching
    # up the line. This is important if given a URL that doesn't support
    # OEmbed. The following are known errors:
    # * Net::* errors like Net::HTTPBadResponse
    # * JSON::JSONError errors like JSON::ParserError
    if defined?(::JSON) && $!.is_a?(::JSON::JSONError) || $!.class.to_s =~ /\ANet::/
      raise OEmbed::UnknownResponse, res && res.respond_to?(:code) ? res.code : 'Error'
    else
      raise $!
    end
end

def extract_json_for_opengraph_link(url,provider)
  values = OpenGraph.fetch(url).to_json
end

def extract_json_for_scrape_link(url,provider)
  if provider["name"] == "GoodReads"
    scrape_goodreads_link(url)
  end
end

def scrape_goodreads_link(url)
  doc = Nokogiri::HTML(open(url))

  values = {}

  # Extract thumbnail_url
  image = doc.at_xpath('//*[@id="coverImage"]')
  if image != nil
    values["thumbnail_url"] = image['src']
  end

  # Extract title
  title = doc.at_xpath('//*[@id="bookTitle"]')
  if title != nil
    values["title"] = title.inner_text.strip
  end

  # Extract description
  description = doc.at_xpath('//*[starts-with(@id, "freeTextContainer")]')
  if title != nil
    values["description"] = description.inner_text.strip
  end

  # Extract Author
  authors = []
  doc.xpath('//*[@id="bookAuthors"]/span[2]/a[*]/span').each do |author|
    authors.push author.text
  end

  if authors.count > 0
    values["author_name"] = authors.join(",")
  end

  puts values.to_s 
end

urls.each do |url|
  provider = find_provider(providers,url)

  if provider == nil
    puts "No provider found."
  else
    puts provider["name"]

    if provider["how"] == "oembed"
      #values = extract_json_for_oembed_link(url,provider)
      #puts values.to_s
    elsif provider["how"] == "opengraph"
      #values = extract_json_for_opengraph_link(url,provider)
      #puts values.to_s
    elsif provider["how"] == "scrape"
      values = extract_json_for_scrape_link(url,provider)
      puts values.to_s
    else
      puts "That provider is not yet supported. Move your lazy ass and write code to handle that type of provider."
    end
  end
end