require 'socket'
require 'zlib'

class Tecepe
    
    FIN = 0x0001;
    SYN = 0x0002;
    RST = 0x0004;
    PSH = 0x0008;
    ACK = 0x0010;
    URG = 0x0020;
    DATA_OFF = 5 << 12;

    attr_accessor :sr_port, :dt_port, :seq_num, :ack_num, :control, :mms

    def initialize(isn = nil)#(port, connect)

        #@socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
        #sockaddr = Socket.sockaddr_in(port, 'localhost')

        #if connect == true then
        #    @socket.connect(sockaddr)
        #elsif connect == false then
        #    @socket.bind(sockaddr)
        #    @socket.listen(1)
        #    puts "Esperando dados da camada de rede..."
        #end

        @seq_num = isn == nil ? rand() : (isn & 0xFFFFFFFF)
        @ack_num = 0
        @control = Tecepe::DATA_OFF
        @mms     = 512
    end

    #def send_segment(msg)
    #    @socket.write(msg)
    #end

    #def recv_segment
    #    msg = ''
    #    while (msg.empty?)
    #        msg = @socket.read
    #    end
    #
    #    return msg
    #end

    #def socket_close
    #    @socket.close
    #end

    def send_segment(segment, port)
        send_socket(segment, port)
    end

    def recv_segment(port)
        segment = recv_socket(port)

        return segment
    end

    def nextSeq(len)
        @seq_num = (seq_num + len) % 0x100000000

        return seq_num
    end

    def calcNextAck(msg, empty = false)
        len = empty ? 1 : msg.length
        @ack_num = (ack_num + len) % 0x100000000

        return ack_num
    end

    def buildSegment(data, flags, empty = false)
        @control = (control | flags)
        len = empty ? 1 : data.length
        header  = [@sr_port, @dt_port, @seq_num, @ack_num, @control, @mms, 0]
        header = header.pack('nnNNnnn')
        segment = [@sr_port, @dt_port, @seq_num, @ack_num, @control, @mms, checksum(header << data), 0]
        segment = segment.pack('nnNNnnnn')
        nextSeq(len)
        @control = Tecepe::DATA_OFF

        return (segment << data)
    end
    
    def sendData(msg, infos, cl_port, sr_port)
        len  = msg.length
        pos  = 0
        mms  = infos[5]
        size = mms - ((Tecepe::DATA_OFF >> 12) * 4)
        while (pos < len)
            pedaco = msg[pos..size]
            calcNextAck(infos[8])
            segmento = buildSegment(pedaco, Tecepe::ACK)
            dump_segment(segmento)
            send_segment(segmento, cl_port)
            resposta = recv_segment(sr_port)
            dump_segment(resposta)
            infos = unpack_info(resposta)

            if (!is_valid_segment(resposta) || infos[3] != @seq_num || !is_flag_set(infos[4], Tecepe::ACK)) then
                abort("Falha na confirmação do segmento")
            end  
            
            pos = pos + size
        end
    end    

    def recvData(infos, cl_port, sr_port)
        msg = ""
        while(true)
            segmento = recv_segment(sr_port)
            dump_segment(segmento)
            infos = unpack_info(segmento)
            break if is_flag_set(infos[4],Tecepe::PSH)

            if (!is_valid_segment(segmento) || infos[3] != @seq_num || !is_flag_set(infos[4], Tecepe::ACK)) then
                abort("Falha na confirmação do segmento")
            end

            msg << infos[8]
            calcNextAck(infos[8])
            resposta = buildSegment('', Tecepe::ACK)
            dump_segment(resposta)
            send_segment(resposta, cl_port)
        end

        return msg
    end

    def close
        @sr_port = 0
        @dt_port = 0
        @ack_num = 0
        @control = Tecepe::DATA_OFF
        @mms     = 512
    end

    def unpack_info(segment)
        header = segment[0..(Tecepe::DATA_OFF >> 12)*4]
        data   = segment[(Tecepe::DATA_OFF >> 12)*4..-1]
        info   = header.unpack('nnNNnnnn')

        info[8] = data
        
        return info
    end   
    
    def is_flag_set(control, flag)
        return (control & flag) != 0
    end

    def flags_desc(control)
        flags = ""

        if (is_flag_set(control, Tecepe::FIN)) then
            flags += 'FIN,'
        end
        if (is_flag_set(control, Tecepe::SYN)) then 
            flags += 'SYN,'
        end
        if (is_flag_set(control, Tecepe::RST)) then
            flags += 'RST,'
        end
        if (is_flag_set(control, Tecepe::PSH)) then 
            flags += 'PSH,'
        end
        if (is_flag_set(control, Tecepe::ACK)) then
            flags += 'ACK,'
        end
        if (is_flag_set(control, Tecepe::URG)) then
            flags += 'URG,'
        end

        if !flags.empty? then
            flags = flags[0..-1]
        end

        return flags
    end

    def dump_segment(segmento)
        infos = unpack_info(segmento)
        #segmento.hexdump
        puts "Src Port: #{infos[0]} ->  Dst Port: #{infos[1]} Flags: #{flags_desc(infos[4])}"
        puts "<SEQ={#{infos[2]}}><ACK={#{infos[3]}}"
    end

    def is_valid_segment(segment)
        info = unpack_info(segment)
        header = [info[0], info[1], info[2], info[3], info[4], info[5], 0]
        header = header.pack('nnNNnnn')

        return checksum(header << info[8]) == info[6]
    end

end

def send_socket(msg, port)
    socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    sockaddr = Socket.sockaddr_in(port, 'localhost')
    while (socket.connect(sockaddr) == false) 
        sleep(1)
    end
    socket.write(msg)
    socket.close

    return msg.length
end

def recv_socket(port)
    msg = ""
    socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    sockaddr = Socket.sockaddr_in(port, 'localhost')
    while (socket.bind(sockaddr) == false) 
        sleep(1)
    end
    socket.listen(10)
    connection = socket.accept
    msg = connection[0].read
    connection[0].close
    socket.close

    return msg
end

def checksum(data)
    crc32        = Zlib::crc32(data.to_s)
    array_16bits = crc32.to_s.unpack('n2')
    soma         = array_16bits[0].to_i + array_16bits[1].to_i

    if soma > 0xFFFF then 
        termo_1 =  soma & 0x0000FFFF
        termo_2 = (soma & 0xFFFF0000) >> 16
        soma    = termo_1 + termo_2
    end
    return (~soma & 0xFFFF)
end



