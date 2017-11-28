require "#{File.expand_path(__FILE__)}/../../tcp"

if ARGV.length < 4 then
    puts "Parâmetros insuficientes!"
    exit
end 

app_port = ARGV[0].to_i
fscl_port = ARGV[1].to_i
fssr_port = ARGV[2].to_i
porta_injecao = ARGV[3].to_i

tcp = Tecepe.new(100)

socket = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
sockaddr = Socket.sockaddr_in(app_port, 'localhost')
socket.bind(sockaddr)
socket.listen(10)

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


while true
    puts "Esperando dados da aplicação"

    connection = socket.accept
    msg = connection[0].read 

    tcp.sr_port = app_port
    tcp.dt_port = 2321

    begin

        puts "Iniciando conexão TCP..."

        segmento = tcp.buildSegment('', Tecepe::SYN, true)
        tcp.dump_segment(segmento)
        tcp.send_segment(segmento, fscl_port)

        resposta = tcp.recv_segment(fssr_port)
        tcp.dump_segment(resposta)
        infos = tcp.unpack_info(resposta)

        if (!tcp.is_valid_segment(resposta) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4],Tecepe::SYN | Tecepe::ACK)) then
            puts "Erro no estabelecimento da conexão"
            tcp.close
        end

        tcp.ack_num = infos[2]
        tcp.calcNextAck(infos[8],true)
        segmento = tcp.buildSegment('',Tecepe::ACK)
        tcp.dump_segment(segmento)
        tcp.send_segment(segmento, fscl_port)

        puts "Conexão estabelecida"
        puts "Transmitindo dados..."
        
        sleep(15)
        tcp.sendData(msg, infos, fscl_port,fssr_port)

        puts "Enviando pedido de PUSH..."
        sleep(10)

        tcp.calcNextAck(infos[8])
        segmento = tcp.buildSegment('',Tecepe::PSH, true)
        tcp.dump_segment(segmento)
        tcp.send_segment(segmento, fscl_port)

        resposta = tcp.recv_segment(fssr_port)
        tcp.dump_segment(resposta)
        infos = tcp.unpack_info(resposta)

        if (!tcp.is_valid_segment(resposta) || infos[3] != tcp.seq_num ) then
            puts "Falha na confirmação do pedido de PUSH"
        end

        puts "Recebendo resposta..."

        msg = tcp.recvData(infos, fscl_port, fssr_port)

        puts "Pedido de PUSH recebido"

        tcp.calcNextAck(infos[8], true)
        segmento = tcp.buildSegment('',Tecepe::ACK)
        tcp.dump_segment(segmento)
        tcp.send_segment(segmento, fscl_port)

        puts "Enviando mensagem para a aplicação..."

        connection[0].write(msg)

        puts "Finalizando conexão"
        sleep(10)

        tcp.calcNextAck(infos[8])
        segmento = tcp.buildSegment('',Tecepe::FIN | Tecepe::ACK, true)
        tcp.dump_segment(segmento)
        sleep(15)
        tcp.send_segment(segmento, fscl_port)

        resposta = tcp.recv_segment(fssr_port)
        tcp.dump_segment(resposta)
        infos = tcp.unpack_info(resposta)

        if (!tcp.is_valid_segment(resposta) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4],Tecepe::ACK)) then
            puts "Erro na confirmação do fechamento da conexão"
            tcp.close
        end

        resposta = tcp.recv_segment(fssr_port)
        tcp.dump_segment(resposta)
        infos = tcp.unpack_info(resposta)

        if (!tcp.is_valid_segment(resposta) || infos[3] != tcp.seq_num || !tcp.is_flag_set(infos[4],Tecepe::FIN | Tecepe::ACK)) then
            puts "Erro no fechamento da conexão"
            tcp.close
        end

        tcp.calcNextAck(infos[8], true)
        segmento = tcp.buildSegment('',Tecepe::ACK, true)
        tcp.dump_segment(segmento)
        tcp.send_segment(segmento, fscl_port)

        puts "Conexão fechada"

        tcp.close

    rescue Exception => msg
        puts "Error: #{msg}."
        break
    end

    connection[0].close

end