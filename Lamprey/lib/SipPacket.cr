class SipPacket



  def initialize
    @headers = {} of String => String
    @body = {} of String => String
    @addr = ""
    @bytes = 0

    @mode = -1
    @via = ""

  end

  @[AlwaysInline]
  def tokenize(line,separator=';')
    return line.separator
  end

  def process
    @headers.each_key do |key|
      value = @headers[key]
      case key
      when "INVITE sip"
        @mode = 1 #invite
        #invite_line = value.split(';')
        inv = tokenize value
        @invite_clauses = inv
        @invite_line = value
        print "INVITE DETECTED"

      when "REGISTER sip"
        print "REGISTER DETECTED"
        @header_line = value

        @mode = 2 #register
      when "Via"
        print "Via Detected"
        @via_line = value

      end
    end
  end

  def interpret (addr,packet,bytes)
    @addr = addr
    @bytes = bytes
    @cached = String.new(packet.to_slice[0,bytes])

    state = 0
    packet.each_line do |line|
      next_state = state
      l = line.rstrip
      if state == 1
        state = 2
      end
      if l == ""
        print "SNIP\n"
        state =1
      end


      if state == 0
        k,v = line.split(':',2)
        @headers[k] = v.strip
      end

      if state == 2
        k,v = line.split('=',2)
        @body[k] = v.strip
      end

    end

    process
    print @headers
    print @body

  end




end
