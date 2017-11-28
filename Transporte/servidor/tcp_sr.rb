require "#{File.expand_path(__FILE__)}/../../tcp"

if ARGV.length < 3 then
    puts "Parâmetros insuficientes!"
    exit
end 

#sckt = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
#sckt.connect(Socket.sockaddr_in(ARGV[0].to_i, 'localhost'))
#socket.listen(1)
#socket = TCPServer.new 'localhost', ARGV[0].to_i

#tcp = Tecepe.new(ARGV[1].to_i, false)

fscl_port = ARGV[0].to_i
fssr_port = ARGV[1].to_i
porta_injecao = ARGV[2].to_i

tcp = Tecepe.new(0)


begin
    puts "Perguntando o TMQ."

    send_socket("TMQ", porta_injecao)
    tmq = tcp.recv_segment(fssr_port)
    tmq = tmq.to_i
    #MMS = TMQ - IP_HEADER - ETHERNET_HEADER
    tcp.mms = tmq - 20 - 26

    puts "TMQ: #{tmq}"
    puts "MMS: #{tcp.mms}"
rescue Exception => msg
    puts "Erro ao obter o TMQ."
    puts "Error: #{msg}."
    #tcp.socket_close
    exit
end

while(true)
    puts "Esperando dados da camada de rede..."

    begin
        #segmento = socket.read
        segmento = tcp.recv_segment(fssr_port)

        puts "Segmento recebido"

        tcp.dump_segment(segmento)

        if !tcp.is_valid_segment(segmento) then
            puts "Segmento corrompido."
        end

        segmento = tcp.unpack_info(segmento)

        if !tcp.is_flag_set(segmento[4], Tecepe::SYN) then
            puts "TCP Error: Nenhuma conexão ativa."
        end

        tcp.ack_num = segmento[2]
        tcp.calcNextAck(segmento[8],true)
        tcp.dt_port = segmento[0]
        tcp.sr_port = segmento[1]
        resposta = tcp.buildSegment('',Tecepe::SYN | Tecepe::ACK, true)
        tcp.dump_segment(resposta)
        #socket.write(resposta)
        tcp.send_segment(resposta, fscl_port)

        #segmento = socket.read
        segmento = tcp.recv_segment(fssr_port)
        tcp.dump_segment(segmento)
        infos = tcp.unpack_info(segmento)

        if (!tcp.is_valid_segment(resposta) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4],Tecepe::ACK)) then
            puts "Erro na confirmação"
            tcp.close
        end

        puts "Conexão estabelecida."
        puts "Recebendo dados..."

        msg = tcp.recvData(infos, fscl_port, fssr_port)

        puts "Pedido de PUSH recebido"

        tcp.calcNextAck(infos[8],true)
        resposta = tcp.buildSegment('',Tecepe::ACK)
        tcp.dump_segment(resposta)
        #socket.write(resposta)
        tcp.send_segment(resposta, fscl_port)

        puts "Enviando mensagem para a aplicação..."

        app = Socket.new Socket::AF_INET, Socket::SOCK_STREAM

        if app == false then
            puts "Socket falhou."
            break
        end

        app.connect(Socket.sockaddr_in(tcp.sr_port, 'localhost'))
        
        app.write(msg)

        puts "Esperando resposta..."

        msg = app.read
        break if msg == false

        app.close

        #puts "Enviando resposta para camada de rede..."
        puts "Enviando resposta para camada de física..."
        sleep(15)

        tcp.sendData(msg, infos, fscl_port, fssr_port)

        puts "Enviando pedido de PUSH..."
        sleep(10)

        tcp.calcNextAck(infos[8])
        resposta = tcp.buildSegment('',Tecepe::PSH,true)
        tcp.dump_segment(resposta)
        #socket.write(resposta)
        tcp.send_segment(resposta, fscl_port)

        #segmento = socket.read
        segmento = tcp.recv_segment(fssr_port)
        tcp.dump_segment(segmento)
        infos = tcp.unpack_info(segmento)

        if (!tcp.is_valid_segment(segmento) || infos[3] != tcp.seq_num) then
            puts "Falha na confirmação do pedido de PUSH."
        end

        puts "Finalizando conexão"

        #segmento = socket.read
        segmento = tcp.recv_segment(fssr_port)
        tcp.dump_segment(segmento)
        infos = tcp.unpack_info(segmento)

        if (!tcp.is_valid_segment(segmento) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4], Tecepe::FIN | Tecepe::ACK)) then
            puts "Erro no fechamento da conexão."
            tcp.close
        end

        tcp.calcNextAck(infos[8], true)
        resposta = tcp.buildSegment('',Tecepe::ACK)
        tcp.dump_segment(resposta)
        #socket.write(resposta)
        tcp.send_segment(resposta, fscl_port)
        
        sleep(15)

        tcp.calcNextAck(infos[8])
        resposta = tcp.buildSegment('',Tecepe::FIN | Tecepe::ACK, true)
        tcp.dump_segment(resposta)
        #socket.write(resposta)
        tcp.send_segment(resposta, fscl_port)

        #segmento = socket.read
        segmento = tcp.recv_segment(fssr_port)
        tcp.dump_segment(segmento)
        infos = tcp.unpack_info(segmento)

        if (!tcp.is_valid_segment(segmento) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4], Tecepe::ACK)) then
            puts "Erro na confirmação do fechamento da conexão."
            tcp.close
        end

        puts "Conexão fechada."

        tcp.close

    rescue Exception => msg
        puts "Error: #{msg}."
        break
    end

end




