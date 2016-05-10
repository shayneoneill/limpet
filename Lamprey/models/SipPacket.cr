class SipPacket

  def log (*a)
    if @verbose
      print a,"\n"
    end
  end
  def dump (a : Hash)
    a.each_key  do |k|
      log k,a[k]
    end
  end

  def initialize
    @headers = {} of String => String
    @body = {} of String => String
    @addr = ""
    @bytes = 0
    @max_forwards = 1
    @mode = :none
    @via = ""
    @rport = false
    @verbose = false
    @branch = "none"
    @to = ""
    @from = ""
    @from_tag = ""
    @cseq = 0
    @cseq_type = ""
    @contact_sip = ""
    @contact_port = "5060"
    @sip_name = ""
    @title = ""
  end

  @[AlwaysInline]
  def tokenize(line,separator=";",&block)
    s = line.split separator
    s.each do |i|
      yield i
    end
  end

  def is_verbose
    @verbose = true
  end

  def process
    log "incoming..."
    @headers.each_key do |key|
      value = @headers[key]
      case key
      when "INVITE sip"
        @mode = :invite #invite
        #invite_line = value.split(';')
        inv = value.split ";"
        @invite_clauses = inv
        @invite_line = value
        log "INVITE DETECTED"

      when "REGISTER sip"
        log "REGISTER DETECTED"
        @register_line = value
        @register_clauses = value.split ";"
        @mode = :register #register
      when "Via"
        log "Via Detected"
        @via_line = value
        pr = value.split(' ')
        @via_protocol = pr[0]
        log "Protocol:",@via_protocol
        theRest = pr[1]
        tokenize theRest do |v|
          b = v.match(/branch\=(.*)/)
          if b
            @branch = b[1]
            log "BRANCH :",@branch
          else
            if v == "rport" #Wants a reciept
              @rport = true
            end
          end
        end
      when "Max-Forwards"
        log "Max Forwards"
        @max_forwards = (value.to_i) - 1
        @can_forward = @max_forwards > 0
      when "Contact"
        log "Contact"
        tokenize value," " do |v|
          b = v.match(/\<(.*)\;/)
          log "RESULTS",b
          if b
            c = b[1]
            split = c.split(':')
            if split[0] == "sip"
              @contact_sip = split[1]
              log "Contact SIP",@contact_sip
              @contact_port = split[2]
            end
            if split[0] == "urn" #@todo This doesnt work yet. Worry about it later
              @contact_urn = split[1]
              log "Contact URN",@contact_URN
            end
            log "CONTACT :",c
          else
            @sip_name = v
          end
        end
      when "To"
        log "To Detected"
        b = value.match(/\<(.*)\>/)
        if b
          c = b[1]
          split = c.split(":")
          @to = c
          log "TO :",@to
        end
        b = value.match(/tag\=(.*)/)
        if b
          @tag = b[1]
          log "TAG",@to_tag
        end
      when "From"
        tokenize value do |v|
          b = v.match(/\<(.*)\>/)
          if b
            @from = b[1]
            log "From:",@from
          end
          b = v.match(/tag\=(.*)/)
          if b
            @from_tag = b[1]
            log "TAG",@from_tag
          end
        end
      when "Allow"
        @capabilities = value.split(",")
        log "Capabilities",@capabilities
      when "Call-ID"
        @call_id = value
        log "Call ID",@call_id
      when "CSeq"
        s = value.split
        @cseq = s[0].to_i
        @cseq_type = s[1]
        log "Call Sequence ",@cseq," => ",@cseq_type
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
    #print "Headers \n"
    #print "===============\n"
    #dump @headers
    #print "Footers \n"
    #print "===============\n"
    #dump @body
  end

  def heading (value)
    @title = value
  end

  def add_header(key,value )
    @headers[key] = value.to_s
  end
  def add_body(key,value)
    @body[key] = value.to_s
  end
  def dump_packet
    r = String.build do |str|
      str << @title
      str << "\r\n"
      @headers.each_key do |v|
        str << v
        str << ": "
        str << @headers[v]
        str << "\r\n"
      end
      str << "\r\n"
      @body.each_key do |v|
        str << v
        str << "="
        str << @body[v]
        str << "\r\n"
      end
    end
    return r
  end

end
