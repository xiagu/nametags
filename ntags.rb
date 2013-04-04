require 'net/http'
require 'rubygems'
require 'json'
require 'nokogiri'
require 'fileutils'
require 'fastimage'

# :main:

# Usage

class NametagGenerator

  # Set up the counts of replaced and unformatted attendees to 0.
  def initialize
    @replaced_count = 0
    @unformatted_count = 0
  end

  # Runs the program using the shell arguments.
  #
  # Call with the following to generate nametags for an event:
  #  ruby ntags.rb output_directory event_id -f format_storage_file
  # The directory will be created if it does not exist.
  #
  # Once you have edited files to position the names, export/save them with with:
  #  ruby ntags.rb -e format_storage_file nametag_p1 [nametag_p2 ...]
  # -e exports the name formatting from the given files.
  #
  # The event id is the number after /events/ in the page url. For example, 
  # in http://www.meetup.com/Bronies-DC/events/53477052/, 53477052 is the
  # event id.
  def run(args)
    if args[0] == "-e" then
      export_name_format(args[1], args[2..(args.length-1)])
    else
      fn = nil
      if args.member? "-f" then
        fn = args.delete_at(args.index("-f") + 1)
        args.delete("-f")
      end
      create_nametags(args[0],fn,args[1])
    end
  end
  
  private

  # Exports the name formats from the given nametag pages to the format
  # storage file.
  def export_name_format(format_fn, nametag_files) 
    format_doc = Nokogiri::XML(File.open(format_fn))
    name_container = format_doc.at_xpath "//*[@id='layer1']"

    nametag_files.each { |f| 
      doc = Nokogiri::XML(File.open(f))

      exports = doc.xpath("//xmlns:g[@inkscape:label='#export']")
      
      exports.each { |e|
        obj = format_doc.at_xpath("//xmlns:g[@id='#{e["id"]}']")
        if obj == nil then
          #       puts e.namespace.inspect
          name_container.add_child(e)
          e.default_namespace = format_doc.children[1].namespace
          #        puts e.namespace.inspect

          #        e.namespace.prefix = nil
          puts "Importing #{e["id"]}"
          #        puts e.inspect
        else # already exists; overwrite
          e.default_namespace = obj.namespace # hopefully this will fix the namespace problems?
          obj.children = e.children
          recursive_namespace_reset(obj, obj.namespace)
          puts "Updating #{e["id"]}"
        end
      }
    }

    File.new(format_fn, "w").write(format_doc.to_xml)
  end

  # Sets the default namespace of the given node and all its children to
  # the given namespace, recursively.
  def recursive_namespace_reset(node, reference_ns) 
    node.default_namespace = reference_ns
    node.children.each { |c| recursive_namespace_reset(c, reference_ns) }
  end

  # Resets the template and sets the arrays to be the img and text fields
  # Returns new template object
  def reset_template(pic_arr, name_arr, nblock_arr, template_ref)
    pic_arr.clear; name_arr.clear; nblock_arr.clear
    template = template_ref.clone
    (1..8).each { |i|
      pic_arr.push(template.at_xpath("//xmlns:image[@id='img#{i}']"))
      name_arr.push(template.at_xpath("//xmlns:text[@id='text#{i}']"))
      nblock_arr.push(template.at_xpath("//xmlns:g[@id='tg_#{i}']"))
    }
    return template
  end
  ##
  #def move_children(element)
  #  name_block.xpath("descendant::xmlns:text").each { |grp|
  #    printf("grp.name=#{grp.name}, #{grp.children.length} children\n")
  #    puts grp["x"]
  #    grp["x"] = (grp["x"].to_f + offset_x).to_s
  #    puts grp["x"]
  #    grp["y"] = (grp["y"].to_f + offset_y).to_s
  #  }
  #end

  # Replaces the automatically populated name field with a saved name format.
  def replace_name(name_container, name_block, text_field, rsvp)
    encoding_options = {
      :invalid           => :replace,
      :undef             => :replace,
      :replace           => '',
      :universal_newline => true
    }
    ascii_name = rsvp["name"].encode Encoding.find('ASCII'), encoding_options

    g_name = "g_#{ascii_name.gsub(" ","_").gsub(/[^a-zA-Z_0-9\.\-]/,"").downcase}"
    saved = nil
    if name_container != nil then
      saved = name_container.at_xpath("xmlns:g[@id='#{g_name}']")
    end
    if saved == nil then
      text_field.content = rsvp["name"]
      name_block["id"] = g_name
      #label is already #export
      puts "XXX No saved name matched #{g_name}"
      @unformatted_count += 1 # count unformatted names
    else    
      puts "--> #{g_name}"
      
      # Get current rect x and y
      orig_rect = name_block.at_xpath("xmlns:rect")
      orig_x = orig_rect["x"].to_f
      orig_y = orig_rect["y"].to_f

      saved_rect = saved.at_xpath("xmlns:rect")
      saved_x = saved_rect["x"].to_f
      saved_y = saved_rect["y"].to_f

      # calculate difference in positions
      offset_x = orig_x - saved_x;
      offset_y = orig_y - saved_y;

      # overwrite saved rectangle location for copying
      #    saved_rect["x"] = orig_x.to_s
      #    saved_rect["y"] = orig_y.to_s

      # try to deep copy to avoid messing up with repeated names
      name_block.children = saved.clone.children
      name_block["id"] = saved["id"]
      #label is already #export

      recursive_namespace_reset(name_block, name_block.namespace)

      if name_block["transform"] == nil then
        name_block["transform"] = ""
      else
        name_block["transform"] += " "
      end
      # append transform. not sure if this is the order I want.
      # hopefully there won't be any transforms on the groups anyway
      name_block["transform"] += "translate(#{offset_x}, #{offset_y})"

      # move all the text elements or something
      
      # recursively modify all children's x and y values just to be safe.
      #    move_children(name_block)
      #=begin
      #   name_block.xpath("descendant::*").each { |grp|
      #    printf("grp.name=#{grp.name}, #{grp.children.length} children\n")
      #    #      printf("grp.value=#{grp.value}\n")
      #    printf "x=#{grp["x"]}=>"
      #    grp["x"] = (grp["x"].to_f + offset_x).to_s if grp["x"] != nil
      #    printf "#{grp["x"]}  y=#{grp["y"]}=>"
      #    grp["y"] = (grp["y"].to_f + offset_y).to_s if grp["y"] != nil
      #    printf "#{grp["y"]}\n"
      #  }
      #   =end
      
      @replaced_count += 1
    end
  end

  #--
  # I should make this more efficient maybe.
  #++
  # Displays a progress bar.
  def progress_bar(done, total, width)
    pb = " "*width
    maxchar = (done.to_f/total*(width - 2)).to_i + 1
    (1..maxchar).each { |i| pb[i] = "=" }
    pb[maxchar] = ">"
    pb[0] = "["
    pb[-1] = "]"
    pb += " #{100*done/total}%"
    return pb
  end

  # Creates nametags in the given directory, using the given format file, for the given event.
  def create_nametags (dirbase, format_storage_fn, event_id="53477052")
    template_ref = nil
    File.open("nametags template.svg") { |f| template_ref = Nokogiri::XML(f) }

    formats = nil; name_container = nil;
    if format_storage_fn != nil then
      formats = Nokogiri::XML(File.open(format_storage_fn))
      name_container = formats.at_xpath "//*[@id='layer1']"
      puts "Read #{name_container.children.length} saved name styles."
    end

    puts "Outputting to #{dirbase}"
    FileUtils.mkpath dirbase unless File.exists? dirbase
    FileUtils.cd dirbase

    src = Net::HTTP.get('api.meetup.com', "/rsvps?key=5b337f5d321971272e21e7617341555&sign=true&event_id=#{event_id}")

    psrc = JSON.parse(src)
    rsvps = psrc["results"] # don't care about meta info

    # total guests
    regged = 0
    guests = 0
    yes = []
    local_urls = []

    puts "Downloading rsvp images:"
    rsvps.length.times { |i| r = rsvps[i]
      # progress bar
      $stderr.print "\r#{progress_bar(i, rsvps.length-1, 60)}"
      next if r['response'] == 'no'

      yes.push r # compile all 'yes' responses
      regged += 1 # count registered attendees
      guests += r['guests'].to_i # count guests

      #  http:// (photos1.meetupstatic.com) (/photos/member/f/3/e/) (member_26751902.jpeg)
      r['photo_url'] =~ /http:\/\/([^\/]*)(\/.*?)(member_.*$)/
      local_urls.push $3
      File.open("#{$3}", "w") { |f| f.write(Net::HTTP.get($1, $2+$3)) }
    }
    
    # Print out list of attendees
    puts
    puts (yes.map { |i| i["name"] }).inspect

    pics = []
    names = []
    nblocks = []
    i = 0
    while i < yes.length
      template = reset_template(pics, names, nblocks, template_ref)

      8.times { |j|
        unless i+j < yes.length then
          names[j].content =  ""
          pics[j].at_xpath("attribute::xlink:href").value = ""
        else
          replace_name(name_container, nblocks[j], names[j], yes[i+j])

          pics[j].at_xpath("attribute::xlink:href").value = local_urls[i+j]

          # adjust picture size and position
          size = FastImage.size(local_urls[i+j])
          width = size[0]; height = size[1]
          if width > height then
            dh = (height.to_f / width * 110)
            pics[j]["width"] = "110"
            pics[j]["height"] = dh.to_s
            pics[j]["y"] = (pics[j]["y"].to_f + (110 - dh)/2).to_s
          elsif height > width then
            dw = (width.to_f / height * 110)
            pics[j]["width"] = dw.to_s
            pics[j]["height"] = "110"
            pics[j]["x"] = (pics[j]["x"].to_f + (110 - dw)/2).to_s
          else
            pics[j]["width"] = "110"
            pics[j]["height"] = "110"
          end        
        end
      }
      
      # Output nametag page
      nt_fn = "nametags p #{i/8}.svg"
      f = File.new(nt_fn, "w")
      f.write(template.to_xml)
      f.close()
      puts "WROTE '#{nt_fn}'\n"
      
      i += 8
    end
    
    # (img.attribute "x").value
    # pic1 = (template.xpath "//xmlns:rect[@id='pic1']").first # selects pic1
    #IO.read('image.png')[0x10..0x18].unpack('NN')

    puts
    puts "Used #{@replaced_count} premade names. #{@unformatted_count} must be formatted."
    puts "Total attendees: #{regged+guests} (#{regged} regged, #{guests} guests)"
    # idea: make a page-by-page breakdown
  end

end

ng = NametagGenerator.new
ng.run(ARGV)
